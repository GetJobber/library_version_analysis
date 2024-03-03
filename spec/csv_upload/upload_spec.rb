require "csv_upload/upload"
require "library_version_analysis/library_tracking"

RSpec.describe CsvUpload::Upload do
  describe "#upload" do
    context 'when only libraries' do
      let(:library_csv) do
        <<~CSV
        #name,owner,current_version

        lib1, team1, 1.2.3
        lib2, team1, 3.2.1 
        CSV
      end

      let(:results) { {} }

      before(:each) do
        allow(subject).to receive(:get_file).and_return(StringIO.new(library_csv))
      end

      it 'has the correct keys' do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expected_keys = ["libraries", "source", "repository"]
          expect(expected_keys.to_set == json.keys.to_set).to be_truthy
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end

      it 'has the correct number of libraries' do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expect(json["libraries"].length).to eq(2)
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end

      it 'source is correct' do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expect(json["source"]).to eq("CSV")
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end

      it 'repository is correct' do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expect(json["repository"]).to eq("proj")
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end

      it "has correct keys in a library" do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expected_keys = ["name", "owner", "version"]
          expect(expected_keys.to_set == json["libraries"].first.keys.to_set).to be_truthy
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end

      it "has correct keys in a library" do
        expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
          json = JSON.parse(data)
          expect(json["libraries"].first["name"]).to eq("lib1")
          expect(json["libraries"].first["owner"]).to eq("team1")
          expect(json["libraries"].first["version"]).to eq("1.2.3")
        end

        subject.upload(project: "proj", csv_file: 'test.csv')
      end
    end
  end

  context "with full data" do
    let(:library_csv) do
      <<~CSV
      #name,owner,current_version

      lib1, team1, 1.2.3
      lib2, team1, 3.2.1 

      #name,new_version
      lib1,1.2.4
      #library,identifier,assigned_severity,state
      lib1,CVE_xxx,critical,OPEN
      CSV
    end

    let(:results) { {} }

    before(:each) do
      allow(subject).to receive(:get_file).and_return(StringIO.new(library_csv))
    end

    it 'has the correct keys' do
      expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
        json = JSON.parse(data)
        expected_keys = ["libraries", "source", "repository", "new_versions", "vulnerabilities"]
        expect(expected_keys.to_set == json.keys.to_set).to be_truthy
      end

      subject.upload(project: "proj", csv_file: 'test.csv')
    end

    it "has correct keys in new_version" do
      expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
        json = JSON.parse(data)
        expected_keys = ["name", "version"]
        expect(expected_keys.to_set == json["new_versions"].first.keys.to_set).to be_truthy
      end

      subject.upload(project: "proj", csv_file: 'test.csv')
    end

    it "has correct keys in a library" do
      expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
        json = JSON.parse(data)
        expect(json["new_versions"].first["name"]).to eq("lib1")
        expect(json["new_versions"].first["version"]).to eq("1.2.4")
      end

      subject.upload(project: "proj", csv_file: 'test.csv')
    end

    it "has correct keys in vulnerabilities" do
      expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
        json = JSON.parse(data)
        expected_keys = ["library", "identifier", "assigned_severity", "state"]
        expect(expected_keys.to_set == json["vulnerabilities"].first.keys.to_set).to be_truthy
      end

      subject.upload(project: "proj", csv_file: 'test.csv')
    end

    it "has correct keys in a vulnerabilities" do
      expect(LibraryVersionAnalysis::LibraryTracking).to receive(:upload) do |data|
        json = JSON.parse(data)
        expect(json["vulnerabilities"].first["library"]).to eq("lib1")
        expect(json["vulnerabilities"].first["identifier"]).to eq("CVE_xxx")
        expect(json["vulnerabilities"].first["assigned_severity"]).to eq("critical")
        expect(json["vulnerabilities"].first["state"]).to eq("OPEN")
      end

      subject.upload(project: "proj", csv_file: 'test.csv')
    end
  end
end
