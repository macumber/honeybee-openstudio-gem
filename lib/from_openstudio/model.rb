# *******************************************************************************
# Honeybee OpenStudio Gem, Copyright (c) 2020, Alliance for Sustainable
# Energy, LLC, Ladybug Tools LLC and other contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER(S) AND ANY CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER(S), ANY CONTRIBUTORS, THE
# UNITED STATES GOVERNMENT, OR THE UNITED STATES DEPARTMENT OF ENERGY, NOR ANY OF
# THEIR EMPLOYEES, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
# OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

require 'honeybee/model'

require 'openstudio'

module Honeybee
  class Model

    # Create Ladybug Energy Model JSON from OpenStudio Model
    def self.translate_from_openstudio(openstudio_model)
      hash = {}
      hash[:type] = 'Model'
      Model.new(hash)
    end

    # Create Ladybug Energy Model JSON from OSM file
    def self.translate_from_osm_file(file)
      vt = OpenStudio::OSVersion::VersionTranslator.new
      openstudio_model = vt.loadModel(file)
      raise "Cannot load OSM file at '#{}'" if openstudio_model.empty?
      self.translate_from_openstudio(openstudio_model.get)
    end

    # Create Ladybug Energy Model JSON from gbXML file
    def self.translate_from_gbxml_file(file)
      translator = OpenStudio::GbXML::GbXMLReverseTranslator.new
      openstudio_model = translator.loadModel(file)
      raise "Cannot load gbXML file at '#{}'" if openstudio_model.empty?
      self.translate_from_openstudio(openstudio_model.get)
    end

  end # Model
end # Honeybee