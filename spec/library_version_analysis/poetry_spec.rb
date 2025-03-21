require "spec_helper"

RSpec.describe LibraryVersionAnalysis::Poetry do
  let(:github_repo) { "test-repo" }
  subject(:poetry) { described_class.new(github_repo) }

  describe "#initialize" do
    it "initializes with a github repo" do
      expect(poetry.instance_variable_get(:@github_repo)).to eq(github_repo)
    end
  end

  describe "#get_versions" do
    let(:source) { "test-source" }
    let(:github) { instance_double(LibraryVersionAnalysis::Github) }

    before do
      allow(LibraryVersionAnalysis::Github).to receive(:new).and_return(github)
    end

    it "returns parsed results and metadata" do
      expect(github).to receive(:get_dependabot_findings)
        .with({}, kind_of(LibraryVersionAnalysis::MetaData), github_repo, source)
      
      parsed_results, meta_data = poetry.get_versions(source)
      
      expect(parsed_results).to be_a(Hash)
      expect(meta_data).to be_a(LibraryVersionAnalysis::MetaData)
    end
  end

  describe "#add_dependabot_findings" do
    let(:parsed_results) { {} }
    let(:meta_data) { LibraryVersionAnalysis::MetaData.new }
    let(:source) { "test-source" }
    let(:github) { instance_double(LibraryVersionAnalysis::Github) }

    before do
      allow(LibraryVersionAnalysis::Github).to receive(:new).and_return(github)
    end

    it "calls get_dependabot_findings on github instance" do
      expect(github).to receive(:get_dependabot_findings)
        .with(parsed_results, meta_data, github_repo, source)
      
      poetry.add_dependabot_findings(parsed_results, meta_data, github_repo, source)
    end
  end
end 