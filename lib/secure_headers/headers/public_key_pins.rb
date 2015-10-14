module SecureHeaders
  class PublicKeyPinsConfigError < StandardError; end
  class PublicKeyPins < Header
    HPKP_HEADER_NAME = "Public-Key-Pins"
    HASH_ALGORITHMS = [:sha256]
    DIRECTIVES = [:max_age]
    CONFIG_KEY = :hpkp

    class << self
      def make_header(config)
        header = new(config)
        [header.name, header.value]
      end

      def symbol_to_hyphen_case sym
        sym.to_s.gsub('_', '-')
      end
    end

    def initialize(config=nil)
      return if config.nil?
      @config = config
      self.class.validate_config!(config) if ENV['RAILS_ENV'] == "development"

      @pins = @config.fetch(:pins, nil)
      @report_uri = @config.fetch(:report_uri, nil)
      @app_name = @config.fetch(:app_name, nil)
      @enforce = !!@config.fetch(:enforce, nil)
      @include_subdomains = !!@config.fetch(:include_subdomains, nil)
      @tag_report_uri = !!@config.fetch(:tag_report_uri, nil)
    end

    def name
      base = HPKP_HEADER_NAME
      if !@enforce
        base += "-Report-Only"
      end
      base
    end

    def value
      header_value = [
        generic_directives,
        pin_directives,
        report_uri_directive,
        subdomain_directive
      ].compact.join('; ').strip
    end

    def self.validate_config!(config)
      return if config.nil? || config == SecureHeaders::OPT_OUT
      raise PublicKeyPinsConfigError.new("config must be a hash.") unless config.is_a? Hash

      if !config[:max_age]
        raise PublicKeyPinsConfigError.new("max-age is a required directive.")
      elsif config[:max_age].to_s !~ /\A\d+\z/
        raise PublicKeyPinsConfigError.new("max-age must be a number.
                                          #{config[:max_age]} was supplied.")
      elsif config[:pins] && config[:pins].length < 2
        raise PublicKeyPinsConfigError.new("A minimum of 2 pins are required.")
      end
    end

    def pin_directives
      return nil if @pins.nil?
      @pins.collect do |pin|
        pin.map do |token, hash|
          "pin-#{token}=\"#{hash}\"" if HASH_ALGORITHMS.include?(token)
        end
      end.join('; ')
    end

    def generic_directives
      DIRECTIVES.collect do |directive_name|
        build_directive(directive_name) if @config[directive_name]
      end.join('; ')
    end

    def build_directive(key)
      "#{self.class.symbol_to_hyphen_case(key)}=#{@config[key]}"
    end

    def report_uri_directive
      return nil if @report_uri.nil?

      if @tag_report_uri
        @report_uri = "#{@report_uri}?enforce=#{@enforce}"
        @report_uri += "&app_name=#{@app_name}" if @app_name
      end

      "report-uri=\"#{@report_uri}\""
    end


    def subdomain_directive
      @include_subdomains ? 'includeSubDomains' : nil
    end
  end
end
