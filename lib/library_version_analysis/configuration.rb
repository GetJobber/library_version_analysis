# lib/library_version_analysis/configuration.rb
module LibraryVersionAnalysis
  module Configuration
    @config = {}
    @config_file_path = File.join(Dir.pwd, '/config/library_version_analysis.yml')

    def self.set(key, value)
      @config[key] = value
    end

    def self.get(key)
      @config.fetch(key, nil)
    end

    def self.keys
      @config.keys
    end

    def self.config_file_path=(path)
      @config_file_path = path
    end

    def self.config_file_path
      @config_file_path
    end

    def self.configure
      if File.exist?(@config_file_path)
        yaml_config = YAML.load_file(@config_file_path)
      else
        yaml_config = {}
        puts "No config file found at #{@config_file_path}! Using defaults." if LibraryVersionAnalysis.dev_output?
      end

      @config[:default_owner_name] = yaml_config.fetch("default_owner_name", :unknown).to_sym
      @config[:special_case_ownerships] = yaml_config.fetch("special_case_ownerships", {})
    end
  end
end