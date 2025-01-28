#!/usr/bin/env ruby
require "bundler/setup"
require "library_version_analysis"

require "pry"

LibraryVersionAnalysis::Analyze.go("Jobber", "npm")
LibraryVersionAnalysis::Analyze.go("Jobber", "gemfile")

