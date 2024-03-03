#!/usr/bin/env ruby
require "bundler/setup"
require "csv_upload"

require "pry"

CsvUpload::Upload.go(project: "proj", csv_file: "testAll.csv")


