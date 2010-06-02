require 'builder'
require 'rubygems'
require 'fileutils'
require 'nokogiri'
require "#{$path}tide_converter.rb"
#require "#{$path}/ms-mascot/lib/ms/mascot/submit.rb"
include Process

#file == input file
#database == type of fasta database to use, e.g. "human"
#enzyme == the enzyme to use in the search, e.g. trypsin
#run == which run, or iteration, this is
# options (All options's default to true):
#     :omssa =>   true | false
#     :xtandem => true | false
#     :crux =>    true | false
#     :sequest => true | false
#     :mascot =>  true | false
class Search
    def initialize(file, database, enzyme, run, opts={})
        @opts = opts
        @run = run
        @enzyme = enzyme
        @database = database
        @file = file
        @outputFiles = []
    end
    
    def run
        puts "\n----------------"
        puts "Running search engines..."
        
        if @opts[:xtandem] == true
            runTandem
        end
        
        if @opts[:omssa] == true
			runOMSSA
        end
		
        if @opts[:tide] == true
        	database = extractDatabase(@database)
        	path = "#{$path}../../crux/tide/"
			
        	#pid = fork {exec("#{path}tide-index --fasta #{database} --enzyme #{@enzyme} --digestion full-digest")}
			#waitpid(pid, 0)
			
			#Forward
            pid = fork {exec("#{path}tide-import-spectra --in #{@file}.ms2 -out #{@file}-forward_tide.spectrumrecords")}
			waitpid(pid, 0)
			
            pid = fork {exec("#{path}tide-search --proteins #{database}.protix --peptides #{database}.pepix --spectra #{@file}-forward_tide.spectrumrecords > #{@file}-forward_tide_#{@run}.results")}
			waitpid(pid, 0)
			
			TideConverter.new("#{@file}-forward_tide_#{@run}", @database, @enzyme).convert
        end
        
        if @opts[:sequest] == true
            #exec("") if fork == nil
        end
        
        if @opts[:mascot] == true
            #exec("") if fork == nil
        end
        
        #Wait for all the processes to finish before moving on
        waitForEverything
        
        #Convert X!Tandem files
        if @opts[:xtandem] == true
            convertTandemOutput
            waitForEverything
        end
        
        @outputFiles
    end
    
    def runTandem
        #Forward search
        createTandemInput(false)
        
        exec("#{$path}../../tandem-linux-10-01-01-4/bin/tandem.exe #{$path}../data/forwardTandemInput.xml") if fork == nil
            
        #Decoy search
        createTandemInput(true)
        
        exec("#{$path}../../tandem-linux-10-01-01-4/bin/tandem.exe #{$path}../data/decoyTandemInput.xml") if fork == nil
    end
    
    def createTandemInput(decoy)
        if decoy
            file = File.new("#{$path}../data/decoyTandemInput.xml", "w+")
        else
            file = File.new("#{$path}../data/forwardTandemInput.xml", "w+")
        end
            
        xml = Builder::XmlMarkup.new(:target => file, :indent => 4)
        xml.instruct! :xml, :version => "1.0"
            
        notes = {'list path, default parameters' => "#{$path}../../tandem-linux-10-01-01-4/bin/default_input.xml",
                 'list path, taxonomy information' => "#{$path}../data/taxonomy.xml",
                 'spectrum, path' => "#{@file}.mgf",
                 'protein, cleavage site' => "#{getTandemEnzyme}",
                 'scoring, maximum missed cleavage sites' => 50}
        
        if decoy
            notes['protein, taxon'] = "#{@database}-r"
            notes['output, path'] = "#{@file}-decoy_tandem_#{@run}.xml"
        else
            notes['protein, taxon'] = "#{@database}"
            notes['output, path'] = "#{@file}-forward_tandem_#{@run}.xml"
        end
                 
        xml.bioml do 
            notes.each do |label, path|
                xml.note(path, :type => "input", :label => label)
            end
        end
            
        file.close
    end
    
    def runOMSSA
        forward = "#{@file}-forward_omssa_#{@run}.pep.xml"
        decoy = "#{@file}-decoy_omssa_#{@run}.pep.xml"
        
        #Forward search
        exec("#{$path}../../omssa-2.1.7.linux/omssacl -fm #{@file}.mgf -op #{forward} -e #{getOMSSAEnzyme} -d #{extractDatabase(@database)}") if fork == nil
        
        #Decoy search
        exec("#{$path}../../omssa-2.1.7.linux/omssacl -fm #{@file}.mgf -op #{decoy} -e #{getOMSSAEnzyme} -d #{extractDatabase(@database + "-r")}") if fork == nil
        
        @outputFiles << [forward, decoy]
    end
    
    def waitForEverything
        begin
            Process.wait while true
        
        rescue SystemCallError
            #No need to do anything here, just go
        end
    end
    
    def convertTandemOutput
        #Convert to pepXML format
        file1 = "#{@file}-forward_tandem_#{@run}.xml"
        file2 = "#{@file}-decoy_tandem_#{@run}.xml"
        pepFile1 = file1.chomp(".xml") + ".pep.xml"
        pepFile2 = file2.chomp(".xml") + ".pep.xml"
        @outputFiles << [pepFile1, pepFile2]
        
        exec("/usr/local/src/tpp-4.3.1/build/linux/Tandem2XML #{file1} #{pepFile1}") if fork == nil
        exec("/usr/local/src/tpp-4.3.1/build/linux/Tandem2XML #{file2} #{pepFile2}") if fork == nil
    end
    
    def extractDatabase(database)
        doc = Nokogiri::XML(IO.read("#{$path}../data/taxonomy.xml"))
        return doc.xpath("//taxon[@label=\"#{database}\"]//file/@URL")
    end
    
    def getOMSSAEnzyme
        doc = Nokogiri::XML(IO.read("#{$path}../../omssa-2.1.7.linux/OMSSA.xsd"))
        return doc.xpath("//xs:enumeration[@value=\"#{@enzyme}\"]/@ncbi:intvalue")
    end
    
    def getTandemEnzyme
        doc = Nokogiri::XML(IO.read("#{$path}../../tandem-linux-10-01-01-4/enzymes.xml"))
        return doc.xpath("//enzyme[@name=\"#{@enzyme}\"]/@symbol")
    end
end
