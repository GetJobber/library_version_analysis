require "net/http"

module LibraryVersionAnalysis
  class LibraryTracking
    def self.upload(json_data)
      zipped_data = Zlib::Deflate.deflate(json_data)

      uri = URI(ENV["LIBRARY_UPLOAD_URL"])
      puts "  updating server at #{uri}" if LibraryVersionAnalysis.dev_output?
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 300
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/zip')
      req["X-Upload-Key"] = ENV["UPLOAD_KEY"]
      req.body = zipped_data
      res = http.request(req)
      puts "response #{res.code}:#{res.msg}\n#{res.body}" if LibraryVersionAnalysis.dev_output?
    end
  end
end
