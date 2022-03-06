RSpec.describe LibraryVersionAnalysis do
  it "has a version number" do
    expect(LibraryVersionAnalysis::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(LibraryVersionAnalysis::Analyze.respond).to eq("Do that Analyze")
  end
end
