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

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

To run the shell script locally, you must first set up the environment variables in the `.env.local` file.
To generate the Github token, follow these steps:
1. From any page on Github, click your icon at the top right, and click Settings
2. Click Developer Settings in the left panel
3. Click Personal Access Tokens and then `Tokens Classic`
4. Click Generate New Token -> Generate new token (classic)
5. Create a token with the `Repo` scope enabled

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
