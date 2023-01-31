require "library_version_analysis/analyze"
require "library_version_analysis/check_version_status"
require "library_version_analysis/github"
require "library_version_analysis/online"
require "library_version_analysis/npm"
require "library_version_analysis/version"
require "library_version_analysis/slack_notify"
require "pry-byebug"

module LibraryVersionAnalysis
  class Error < StandardError; end
  # Your code goes here...
end
