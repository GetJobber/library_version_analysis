# lib/library_version_analysis/configuration.rb
module LibraryVersionAnalysis
  module Configuration
    @config = {}

    def self.set(key, value)
      @config[key] = value
    end

    def self.get(key)
      @config.fetch(key, nil)
    end

    def self.keys
      @config.keys
    end

    def self.configure
      config_file_path = File.join(Dir.pwd, '/config/library_version_analysis.yml')

      if File.exist?(config_file_path)
        yaml_config = YAML.load_file(config_file_path)
      else
        yaml_config = {}
        puts "No config file found! Using defaults." if DEV_OUTPUT
      end

      @config[:default_owner_name] = yaml_config.fetch("default_owner_name", :unknown).to_sym
      @config[:special_case_ownerships] = yaml_config.fetch("special_case_ownerships", {})
    end
  end
end