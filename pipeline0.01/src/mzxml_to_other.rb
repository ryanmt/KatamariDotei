require 'rubygems'
require "#{$path}ms-msrun/lib/ms/msrun"

class MzXMLToOther
    def initialize(type, file, hardklor)
        @type = type
        @file = file
        @hardklor = hardklor
    end

    def convert
        puts "\n----------------"
        puts "Transforming mzXML file to #{@type} format..."
        
        runHardklor if @hardklor
        
        if @type == "mgf"
            Ms::Msrun.open(@file) do |ms|
                file = @file.chomp(".mzXML")
                file += ".mgf"
                File.new(file, "w+").close
                File.open(file, 'w') do |f|
                    f.puts ms.to_mgf() 
                end
            end
        else
            exec("wine mzxml2search.exe -#{@type} #{@file}") if fork == nil
            Process.wait
        end
    end
    
    private
    
    def runHardklor
        puts "Running Hardklor..."
        Dir.chdir("#{$path}hardklor/") do
            outputFile = @file.chomp(".mzXML")
            exec("hardklor #{@file} #{outputFile}.hardklor") if fork == nil
            Process.wait
        end
    end
end