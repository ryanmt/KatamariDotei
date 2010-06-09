require "#{File.dirname($0)}/pepxml.rb"
require 'nokogiri'

#Creates an mzIdentML file from a file type created by a search engine, using the format classes such as PepXML.
#Takes a Format object
class Search2mzIdentML
	def initialize(format)
		@format = format
	end
	
	#Starts the Nokogiri build process. Other methods build the different parts of the file. Root is depth 0
	def convert
		puts "Creating file..."
		
		file = createFile
		
		builder = Nokogiri::XML::Builder.new(:encoding => 'UTF-8') do |xml|
			xml.mzIdentML(:id => "",
				:version => "1.0.0",
				'xsi:schemaLocation' => "http://psidev.info/psi/pi/mzIdentML/1.0 ../schema/mzIdentML1.0.0.xsd",
				'xmlns' => "http://psidev.info/psi/pi/mzIdentML/1.0",
				'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance",
				:creationDate => @format.date) {
					cvList(xml)
					provider(xml)
					sequenceCollection(xml)
					analysisCollection(xml)
					analysisProtocolCollection(xml)
					dataCollection(xml)
				}
		end
		
		file.puts builder.to_xml
		file.close
	end
	
	private
	
	def createFile
		if @format.type == "pepxml"
			return File.new("#{@format.file.chomp('.pep.xml')}-test.mzid", "w+")
		end
	end
	
	#Depth 1
	def cvList(xml)
		xml.cvList {
			xml.cv(:id => "PSI-MS", :fullName => "Proteomics Standards Initiative Mass Spectrometry Vocabularies", :URI => "http://psidev.cvs.sourceforge.net/viewvc/*checkout*/psidev/psi/psi-ms/mzML/controlledVocabulary/psi-ms.obo", :version => "2.32.0")
			xml.cv(:id => "UNIMOD", :fullName => "UNIMOD", :URI => "http://www.unimod.org/obo/unimod.obo")
			xml.cv(:id => "UO", :fullName => "UNIT-ONTOLOGY", :URI => "http://obo.cvs.sourceforge.net/*checkout*/obo/obo/ontology/phenotype/unit.obo")
		}
	end
	
	#Depth 1
	def provider(xml)
		xml.Provider(:Software_ref => "search2mzIdentML.rb", :id => "PROVIDER") {
			xml.ContactRole(:Contact_ref => "PERSON_DOC_OWNER") {
				xml.role {
					xml.cvParam(:accession => "MS:1001271", :name => "researcher", :cvRef => "PSI-MS")
				}
			}
		}
	end
	
	#Depth 1
	def sequenceCollection(xml)
		xml.SequenceCollection {
			dBSequences(xml)
			peptides(xml)
		}
	end
	
	#Depth 2
	def dBSequences(xml)
		proteins = @format.proteins
		
		proteins.each do |protein|
			xml.DBSequence(:id => protein[2], :SearchDatabase_ref => @format.databaseName, :accession => protein[0]) {
				xml.cvParam(:accession => "MS:1001088", :name => "protein description", :cvRef => "PSI-MS", :value => protein[1])
			}
		end
	end
	
	#Depth 2
	def peptides(xml)
		peptides = @format.peptides
		
		peptides.each do |peptide|
			xml.Peptide(:id => peptide[0]) {
				xml.peptideSequence peptide[1]
			}
		end
	end
	
	#Depth 1
	def analysisCollection(xml)
		xml.AnalysisCollection {
			xml.SpectrumIdentification(:id => "SI", :SpectrumIdentificationProtocol_ref => "SIP", :SpectrumIdentificationList_ref => "SIL_1", :activityDate => @format.date) {
				xml.InputSpectra(:SpectraData_ref => @format.file)
				xml.SearchDatabase(:SearchDatabase_ref => @format.databaseName)
			}
		}
	end
	
	#Depth 1
	def analysisProtocolCollection(xml)
		xml.AnalysisProtocolCollection {
			SpectrumIdentificationProtocol(xml)
		}
	end
	
	#Depth 2
	def SpectrumIdentificationProtocol(xml)
		xml.SpectrumIdentificationProtocol(:id => "SIP", :AnalysisSoftware_ref => @format.searchEngine) {
			xml.SearchType {
				#Don't know of any value other than "ms-ms search"
				xml.cvParam(:accession => "MS:1001083", :name => "ms-ms search", :cvRef => "PSI-MS", :value => "")
			}
			xml.Threshold {
				if @format.threshold == 0
					xml.cvParam(:accession => "MS:1001494", :name => "no threshold", :cvRef => "PSI-MS")
				else
					xml.cvParam(:accession => "MS:?", :name => "?", :cvRef => "PSI-MS", :value => @format.threshold)
				end
			}
		}
	end
	
	#Depth 1
	def dataCollection(xml)
		xml.DataCollection {
			xml.Inputs {}
			xml.AnalysisData {
				xml.SpectrumIdentificationList(:id => "SIL_1", :numSequencesSearched => @format.numberOfSequences) {
					spectrumIdentificationResult(xml)
				}
			}
		}
	end
	
	#Depth 4
	def spectrumIdentificationResult(xml)
		results = @format.results
		i = 1
		
		results.each do |result|
			xml.SpectrumIdentificationResult(:id => "SIR_#{i}", :spectrumID => "index=#{result.index}", :SpectraData_ref => @format.file) {
				result.items.each do |item|
					ident = item.ident
					siiID = "SII_#{i}_#{ident.id}"
					
					xml.SpectrumIdentificationItem(
						:id => siiID,
						:calculatedMassToCharge => '%.8f' % ident.mass,
						:chargeState => ident.charge,
						:experimentalMassToCharge => '%.8f' % ident.experi,
						:Peptide_ref => ident.pep,
						:rank => ident.rank,
						:passThreshold => ident.pass) {
							spectrumIdentificationItemVals(xml, item, siiID)
						}
				end
			}	if result.items.length > 0	#Schema says that SpectrumIdentificationResult can't be empty
			i += 1
		end
	end
	
	#Depth 6
	def spectrumIdentificationItemVals(xml, item, siiID)
		pepEv = item.pepEvidence
		
		if pepEv != nil
			xml.PeptideEvidence(
				:id => "#{pepEv.id}_#{siiID}",	#The SII ID is added because IDs must be unique.
				:start => pepEv.start,
				:end => pepEv.end,
				:pre => pepEv.pre,
				:post => pepEv.post,
				:missedCleavages => pepEv.missedCleavages,
				:isDecoy => pepEv.isDecoy,
				:DBSequence_Ref => pepEv.DBSequence_Ref)
		end
		
		item.vals.each do |val|
			#Not all pepxml score names have a corresponding mzIdentML value, so those are left out.
			xml.cvParam(:accession => val[0], :name => val[1], :cvRef => "PSI-MS", :value => val[2]) if val[0] != ""
		end
	end
end
