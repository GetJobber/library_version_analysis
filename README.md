# LibraryVersionAnalysis

This is unmaintained library being open sourced for others to learn and fork from.

Patches will not be accepted. Issues are not likely to be responded to.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'library_version_analysis'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install library_version_analysis

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.
To use in development version of this code to analyze Jobber, replace the gem definition with  jgem :enablers, "library_version_analysis", path: "/Users/johnz/workspace/library_version_analysis"


## Jobber Dev
Update the gemfile to read:
jgem :enablers, "library_version_analysis", path: "/Users/johnz/source/library_version_analysis"

then: bundle update --conservative library_version_analysis
ln -s ../library_version_analysis .
source library_version_anaysis/version.sh
library_version_analysis/run.sh


## Contributing

Not supported

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
