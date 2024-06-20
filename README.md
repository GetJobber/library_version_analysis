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

## Updating Version Tag
TODO when I next update, but...

Also remember to update (maybe, we don't know why yet) the bundle_cache_key in circle-ci as per this PR: https://github.com/GetJobber/Jobber/pull/40468/files

## API Tokens
### Github
Used to read dependabot alerts

To create the github token:
1) Under you profile, go to settings
2) Now on the right side, click on Developer settings (near the bottom)
3) Click on Personal access tokens -> Tokens (classic)
4) Create a new classic token, selecting the (repo (all), read:package and read:project) scopes

### Upload Key
The key used by LibraryTracking. See that project for the correct value.

### Google keys
deprecated

### Version Status spreadsheet
deprecated

### Slack token
deprecated

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
