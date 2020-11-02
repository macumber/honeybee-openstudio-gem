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

# import the core objects from which everything inherits
require 'honeybee/extension'
require 'honeybee/model_object'

# import the compound objects that house the other objects
require 'honeybee/construction_set'
require 'honeybee/program_type'

# import the geometry objects
require 'honeybee/geometry/shade'
require 'honeybee/geometry/door'
require 'honeybee/geometry/aperture'
require 'honeybee/geometry/face'
require 'honeybee/geometry/room'

# import the HVAC objects
require 'honeybee/hvac/ideal_air'
require 'honeybee/hvac/template'

# import the construction objects
require 'honeybee/construction/opaque'
require 'honeybee/construction/window'
require 'honeybee/construction/windowshade'
require 'honeybee/construction/shade'
require 'honeybee/construction/air'

# import the material objects
require 'honeybee/material/opaque'
require 'honeybee/material/opaque_no_mass'
require 'honeybee/material/window_gas'
require 'honeybee/material/window_gas_mixture'
require 'honeybee/material/window_gas_custom'
require 'honeybee/material/window_blind'
require 'honeybee/material/window_glazing'
require 'honeybee/material/window_shade'
require 'honeybee/material/window_simpleglazsys'

# import the schedule objects
require 'honeybee/schedule/type_limit'
require 'honeybee/schedule/fixed_interval'
require 'honeybee/schedule/ruleset'

# import the load objects
require 'honeybee/load/setpoint_thermostat'
require 'honeybee/load/setpoint_humidistat'

# import the ventilative cooling objects
require 'honeybee/ventcool/simulation'

require 'openstudio'


module Honeybee
  class Model
    attr_reader :errors, :warnings

    # Read Ladybug Energy Model JSON from disk
    def self.read_from_disk(file)
      hash = nil
      File.open(File.join(file), 'r') do |f|
        hash = JSON.parse(f.read, symbolize_names: true)
      end
      Model.new(hash)
    end

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

    # Load ModelObject from symbolized hash
    def initialize(hash)
      # initialize class variable @@extension only once
      @@extension ||= Extension.new
      @@schema ||= @@extension.schema
      @@standards ||= @@extension.standards

      @hash = hash
      @type = @hash[:type]
      raise 'Unknown model type' if @type.nil?
      raise "Incorrect model type '#{@type}'" unless @type == 'Model'
    end

    # check if the model is valid
    def valid?
      if Gem.loaded_specs.has_key?("json-schema")
        return validation_errors.empty?
      else
        return true
      end
    end

    # return detailed model validation errors
    def validation_errors
      if Gem.loaded_specs.has_key?("json-schema")
        require 'json-schema'
        JSON::Validator.fully_validate(@@schema, @hash)
      end
    end

    def defaults
      @@schema[:components][:schemas][:ModelEnergyProperties][:properties]
    end

    # convert to openstudio model, clears errors and warnings
    def to_openstudio_model(openstudio_model=nil, log_report=true)
      @errors = []
      @warnings = []

      if log_report
        puts 'Starting Model translation from Honeybee to OpenStudio'
      end

      @openstudio_model = if openstudio_model
                            openstudio_model
                          else
                            OpenStudio::Model::Model.new
                          end

      # create all openstudio objects in the model
      create_openstudio_objects(log_report)

      if log_report
        puts 'Done with Model translation!'
      end

      @openstudio_model
    end

    private

    # create OpenStudio objects in the OpenStudio model
    def create_openstudio_objects(log_report=true)
      # assign a standards building type so that David's measures can run
      building = @openstudio_model.getBuilding
      building.setStandardsBuildingType('MediumOffice')

      # initialize a global variable for whether the AFN is used instead of simple ventilation
      $use_simple_vent = true
      if @hash[:properties][:energy][:ventilation_simulation_control]
        vent_sim_control = @hash[:properties][:energy][:ventilation_simulation_control]
        if vent_sim_control[:vent_control_type] && vent_sim_control[:vent_control_type] != 'SingleZone'
          $use_simple_vent = false
          vsim_cntrl = VentilationSimulationControl.new(vent_sim_control)
          $afn_reference_crack = vsim_cntrl.to_openstudio(@openstudio_model)
        end
      end

      # initialize global hashes for various model properties
      $gas_gap_hash = Hash.new  # hash to track gas gaps in case they are split by shades
      $air_boundary_hash = Hash.new  # hash to track any air boundary constructions
      $window_shade_hash = Hash.new  # hash to track any window constructions with shade
      $programtype_setpoint_hash = Hash.new  # hash to track Setpoint objects
      $interior_afn_srf_hash = Hash.new  # track whether an adjacent surface is already in the AFN

      # create all of the non-geometric model elements
      if log_report  # schedules are used by all other objects and come first
        puts 'Translating Schedules'
      end
      if @hash[:properties][:energy][:schedule_type_limits]
        create_schedule_type_limits(@hash[:properties][:energy][:schedule_type_limits])
      end
      if @hash[:properties][:energy][:schedules]
        create_schedules(@hash[:properties][:energy][:schedules])
      end

      if log_report
        puts 'Translating Materials'
      end
      if @hash[:properties][:energy][:materials]
        create_materials(@hash[:properties][:energy][:materials])
      end

      if log_report
        puts 'Translating Constructions'
      end
      if @hash[:properties][:energy][:constructions]
        create_constructions(@hash[:properties][:energy][:constructions])
      end

      if log_report
        puts 'Translating ConstructionSets'
      end
      if @hash[:properties][:energy][:construction_sets]
        create_construction_sets(@hash[:properties][:energy][:construction_sets])
      end

      if log_report
        puts 'Translating ProgramTypes'
      end
      if @hash[:properties][:energy][:program_types]
        create_program_types(@hash[:properties][:energy][:program_types])
      end

      # create the default construction set to catch any cases of unassigned constructions
      if log_report
        puts 'Translating Default ConstructionSet'
      end
      create_default_construction_set

      # create the geometry and add any extra properties to it
      if log_report
        puts 'Translating Room Geometry'
      end
      create_rooms

      unless $window_shade_hash.empty?
        if log_report
          puts 'Translating Window Shading Control'
        end
        create_shading_control
      end

      if log_report
        puts 'Translating HVAC Systems'
      end
      create_hvacs

      if log_report
        puts 'Translating Context Shade Geometry'
      end
      create_orphaned_shades
      create_orphaned_faces
      create_orphaned_apertures
      create_orphaned_doors
    end

    def create_materials(material_dicts, check_existing=false)
      material_dicts.each do |material|
        # check if there's already a material in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getMaterialByName(material[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the material object to the Model
        if add_obj
          material_type = material[:type]
          case material_type
          when 'EnergyMaterial'
            material_object = EnergyMaterial.new(material)
          when 'EnergyMaterialNoMass'
            material_object = EnergyMaterialNoMass.new(material)
          when 'EnergyWindowMaterialGas'
            material_object = EnergyWindowMaterialGas.new(material)
            $gas_gap_hash[material[:identifier]] = material_object
          when 'EnergyWindowMaterialGasMixture'
            material_object = EnergyWindowMaterialGasMixture.new(material)
            $gas_gap_hash[material[:identifier]] = material_object
          when 'EnergyWindowMaterialGasCustom'
            material_object = EnergyWindowMaterialGasCustom.new(material)
            $gas_gap_hash[material[:identifier]] = material_object
          when 'EnergyWindowMaterialSimpleGlazSys'
            material_object = EnergyWindowMaterialSimpleGlazSys.new(material)
          when 'EnergyWindowMaterialBlind'
            material_object = EnergyWindowMaterialBlind.new(material)
          when 'EnergyWindowMaterialGlazing'
            material_object = EnergyWindowMaterialGlazing.new(material)
          when 'EnergyWindowMaterialShade'
            material_object = EnergyWindowMaterialShade.new(material)
          else
            raise "Unknown material type #{material_type}"
          end
          material_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_constructions(construction_dicts, check_existing=false)
      construction_dicts.each do |construction|
        # check if there's already a construction in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getConstructionByName(construction[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the construction object to the Model
        if add_obj
          construction_type = construction[:type]
          case construction_type
          when 'OpaqueConstructionAbridged'
            construction_object = OpaqueConstructionAbridged.new(construction)
          when 'WindowConstructionAbridged'
            construction_object = WindowConstructionAbridged.new(construction)
          when 'WindowConstructionShadeAbridged'
            construction_object = WindowConstructionShadeAbridged.new(construction)
            $window_shade_hash[construction[:identifier]] = construction_object
          when 'ShadeConstruction'
            construction_object = ShadeConstruction.new(construction)
          when 'AirBoundaryConstructionAbridged'
            construction_object = AirBoundaryConstructionAbridged.new(construction)
            $air_boundary_hash[construction[:identifier]] = construction
          else
            raise "Unknown construction type #{construction_type}."
          end
          construction_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_construction_sets(construction_set_dicts, check_existing=false)
      construction_set_dicts.each do |construction_set|
        # check if there's already a construction set in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getDefaultConstructionSetByName(
            construction_set[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the construction set object to the Model
        if add_obj
          construction_set_object = ConstructionSetAbridged.new(construction_set)
          construction_set_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_schedule_type_limits(stl_dicts, check_existing=false)
      stl_dicts.each do |schedule_type_limit|
        # check if there's already a schedule type limit in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getScheduleTypeLimitsByName(
            schedule_type_limit[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the schedule type limit object to the Model
        if add_obj
          schedule_type_limit_object = ScheduleTypeLimit.new(schedule_type_limit)
          schedule_type_limit_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_schedules(schedule_dicts, check_existing=false)
      schedule_dicts.each do |schedule|
        # check if there's already a schedule in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getScheduleByName(schedule[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the schedule object to the Model
        if add_obj
          schedule_type = schedule[:type]
          case schedule_type
          when 'ScheduleRulesetAbridged'
            schedule_object = ScheduleRulesetAbridged.new(schedule)
          when 'ScheduleFixedIntervalAbridged'
            schedule_object = ScheduleFixedIntervalAbridged.new(schedule)
          else
            raise("Unknown schedule type #{schedule_type}.")
          end
          schedule_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_program_types(program_dicts, check_existing=false)
      program_dicts.each do |space_type|
        # check if there's already a space type in the model with the identifier
        add_obj = true
        if check_existing
          object = @openstudio_model.getSpaceTypeByName(space_type[:identifier])
          if object.is_initialized
            add_obj = false
          end
        end

        # add the space type object to the Model
        if add_obj
          space_type_object = ProgramTypeAbridged.new(space_type)
          space_type_object.to_openstudio(@openstudio_model)
        end
      end
    end

    def create_default_construction_set
      # create the materials, constructions and construction set
      create_materials(@@standards[:materials], true)
      create_constructions(@@standards[:constructions], true)
      create_construction_sets(@@standards[:construction_sets], true)

      # write the fractional schedule type and always on schedule if they are not there
      @@standards[:schedule_type_limits].each do |sch_type_limit|
        if sch_type_limit[:identifier] == 'Fractional'
          create_schedule_type_limits([sch_type_limit], true)
        end
      end
      @@standards[:schedules].each do |schedule|
        if schedule[:identifier] == 'Always On'
          create_schedules([schedule], true)
        end
      end

      # set the default construction set to the building level of the Model
      construction_id = 'Default Generic Construction Set'
      construction = @openstudio_model.getDefaultConstructionSetByName(construction_id)
      unless construction.empty?
        os_constructionset = construction.get
        @openstudio_model.getBuilding.setDefaultConstructionSet(os_constructionset)
      end
    end

    def create_rooms
      if @hash[:rooms]
        $air_mxing_array = []  # list to track any air mixing between Rooms

        @hash[:rooms].each do |room|
          room_object = Room.new(room)
          openstudio_room = room_object.to_openstudio(@openstudio_model)

          # for rooms with setpoint objects definied in the ProgramType, make a new thermostat
          if room[:properties][:energy][:program_type] && !room[:properties][:energy][:setpoint]
            thermal_zone = openstudio_room.thermalZone()
            unless thermal_zone.empty?
              thermal_zone_object = thermal_zone.get
              program_type_id = room[:properties][:energy][:program_type]
              setpoint_hash = $programtype_setpoint_hash[program_type_id]
              if not setpoint_hash.nil?  # program type has no setpoint
                thermostat_object = SetpointThermostat.new(setpoint_hash)
                openstudio_thermostat = thermostat_object.to_openstudio(@openstudio_model)
                thermal_zone_object.setThermostatSetpointDualSetpoint(openstudio_thermostat)
                if setpoint_hash[:humidifying_schedule] or setpoint_hash[:dehumidifying_schedule]
                  humidistat_object = ZoneControlHumidistat.new(setpoint_hash)
                  openstudio_humidistat = humidistat_object.to_openstudio(@openstudio_model)
                  thermal_zone_object.setZoneControlHumidistat(openstudio_humidistat)
                end
              end
            end
          end
        end

        # create mixing objects between Rooms
        $air_mxing_array.each do |air_mix_props|
          zone_mixing = OpenStudio::Model::ZoneMixing.new(air_mix_props[0])
          zone_mixing.setDesignFlowRate(air_mix_props[1])
          flow_sch_ref = @openstudio_model.getScheduleByName(air_mix_props[2])
          unless flow_sch_ref.empty?
            flow_sched = flow_sch_ref.get
            zone_mixing.setSchedule(flow_sched)
          end
          source_zone_ref = @openstudio_model.getThermalZoneByName(air_mix_props[3])
          unless source_zone_ref.empty?
            source_zone = source_zone_ref.get
            zone_mixing.setSourceZone(source_zone)
          end
        end
      end
    end

    def create_shading_control
      # assign any shading control objects to windows with shades
      # this is run as a separate step once all logic about construction sets is in place
      sub_faces = @openstudio_model.getSubSurfaces()
      sub_faces.each do |sub_face|
        constr_ref = sub_face.construction
        unless constr_ref.empty?
          constr = constr_ref.get
          constr_name_ref = constr.name
          unless constr_name_ref.empty?
            constr_name = constr_name_ref.get
            unless $window_shade_hash[constr_name].nil?
              window_shd_constr = $window_shade_hash[constr_name]
              os_shd_control = window_shd_constr.to_openstudio_shading_control(@openstudio_model)
              sub_face.setShadingControl(os_shd_control)
            end
          end
        end
      end
    end

    def create_hvacs
      if @hash[:properties][:energy][:hvacs]
        $air_loop_count = 0  # track the total number of air loops in the model
        # gather all of the hashes of the HVACs
        hvac_hashes = Hash.new
        @hash[:properties][:energy][:hvacs].each do |hvac|
          hvac_hashes[hvac[:identifier]] = hvac
          hvac_hashes[hvac[:identifier]]['rooms'] = []
        end
        # loop through the rooms and track which are assigned to each HVAC
        if @hash[:rooms]
          @hash[:rooms].each do |room|
            if room[:properties][:energy][:hvac]
              hvac_hashes[room[:properties][:energy][:hvac]]['rooms'] << room[:identifier]
            end
          end
        end

        hvac_hashes.each_value do |hvac|
          system_type = hvac[:type]
          if system_type == 'IdealAirSystemAbridged'
            ideal_air_system = IdealAirSystemAbridged.new(hvac)
            hvac['rooms'].each do |room_id|
              os_ideal_air = ideal_air_system.to_openstudio(@openstudio_model)
              # enforce a strict naming system for each zone so results can be matched
              os_ideal_air.setName(room_id + ' Ideal Loads Air System')
              zone_get = @openstudio_model.getThermalZoneByName(room_id)
              unless zone_get.empty?
                os_thermal_zone = zone_get.get
                os_ideal_air.addToThermalZone(os_thermal_zone)
              end
            end
          elsif TemplateHVAC.types.include?(system_type)
            template_system = TemplateHVAC.new(hvac)
            os_template_system = template_system.to_openstudio(@openstudio_model, hvac['rooms'])
          end
        end
      end
    end

    def create_orphaned_shades
      if @hash[:orphaned_shades]
        shading_surface_group = OpenStudio::Model::ShadingSurfaceGroup.new(@openstudio_model)
        shading_surface_group.setShadingSurfaceType('Building')
        @hash[:orphaned_shades].each do |shade|
        shade_object = Shade.new(shade)
        openstudio_shade = shade_object.to_openstudio(@openstudio_model)
        openstudio_shade.setShadingSurfaceGroup(shading_surface_group)
        end
      end
    end

    def create_orphaned_faces
      if @hash[:orphaned_faces]
        raise "Orphaned Faces are not translatable to OpenStudio."
      end
    end

    def create_orphaned_apertures
      if @hash[:orphaned_apertures]
        raise "Orphaned Apertures are not translatable to OpenStudio."
      end
    end

    def create_orphaned_doors
      if @hash[:orphaned_doors]
        raise "Orphaned Doors are not translatable to OpenStudio."
      end
    end

    #TODO: create runlog for errors.

  end # Model
end # Honeybee