require "net/http"

module LibraryVersionAnalysis
  class LibraryTracking
    def self.upload(json_data)
      uri = URI(ENV["LIBRARY_UPLOAD_URL"])
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 300
      req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
      req["X-Upload-Key"] = ENV["UPLOAD_KEY"]
      req.body = json_data
      res = http.request(req)
      puts "response #{res.code}:#{res.msg}\n#{res.body}"
    end
  end
end
