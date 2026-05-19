require "library_version_analysis/ownership"

RSpec.describe LibraryVersionAnalysis::Ownership do
  describe ".canonicalize" do
    it "strips leading and trailing colons" do
      expect(described_class.canonicalize(":bizops:")).to eq("bizops")
      expect(described_class.canonicalize(":bizops")).to eq("bizops")
      expect(described_class.canonicalize("bizops:")).to eq("bizops")
    end

    it "strips surrounding double quotes" do
      expect(described_class.canonicalize('"bizops"')).to eq("bizops")
    end

    it "strips surrounding single quotes" do
      expect(described_class.canonicalize("'bizops'")).to eq("bizops")
    end

    it "downcases mixed case input" do
      expect(described_class.canonicalize(":Bizops")).to eq("bizops")
      expect(described_class.canonicalize("BIZOPS")).to eq("bizops")
    end

    it "handles Ruby symbols" do
      expect(described_class.canonicalize(:attention_needed)).to eq("attention_needed")
      expect(described_class.canonicalize(:bizops)).to eq("bizops")
    end

    it "falls back to 'unknown' for nil" do
      expect(described_class.canonicalize(nil)).to eq("unknown")
    end

    it "falls back to 'unknown' for empty string" do
      expect(described_class.canonicalize("")).to eq("unknown")
    end

    it "falls back to 'unknown' for whitespace-only input" do
      expect(described_class.canonicalize("   ")).to eq("unknown")
    end

    it "falls back to 'unknown' for punctuation-only input" do
      expect(described_class.canonicalize(":")).to eq("unknown")
      expect(described_class.canonicalize("::")).to eq("unknown")
      expect(described_class.canonicalize('""')).to eq("unknown")
      expect(described_class.canonicalize("''")).to eq("unknown")
    end

    it "strips surrounding whitespace" do
      expect(described_class.canonicalize("  bizops  ")).to eq("bizops")
      expect(described_class.canonicalize("  :bizops:  ")).to eq("bizops")
    end

    it "is idempotent for representative inputs" do
      [
        ":bizops",
        ":bizops:",
        '"bizops"',
        "'bizops'",
        ":Bizops",
        :attention_needed,
        nil,
        "",
        "   ",
        "bizops",
        "Frontend_Foundations",
      ].each do |input|
        once = described_class.canonicalize(input)
        twice = described_class.canonicalize(once)
        expect(twice).to eq(once), "expected canonicalize to be idempotent for #{input.inspect}, got #{once.inspect} -> #{twice.inspect}"
      end
    end
  end
end
