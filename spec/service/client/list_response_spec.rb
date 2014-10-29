require 'spec_helper'

describe Service::Client::ListResponse do
  let (:response) do
    {
      "current_page" => 5,
      "total_pages" => 1,
      "total_items" => 3,
      "took" => 123,
      "results" => [
        { "id" => 1, "type" => "photo", "score" => 1},
        { "id" => 2, "type" => "photo", "score" => 1},
        { "id" => 3, "type" => "photo", "score" => 1},
      ],
    }
  end

  let (:empty_response) do
    {
      "current_page" => 1,
      "total_pages" => 1,
      "total_items" => 0,
      "took" => 123,
      "results" => [],
    }
  end

  subject { Service::Client::ListResponse.new(20, response, "results", name: "value") }

  describe '#results' do
    it "results the results" do
      expect(subject.results).to eq(response["results"])
    end
  end


  describe '#per_page' do
    it "returns the page size" do
      expect(subject.per_page).to be(20)
    end
  end

  describe '#current_page' do
    it "returns the current page" do
      expect(subject.current_page).to be(5)
    end
  end

  describe '#total_entries' do
    it "returns the total number of entries" do
      expect(subject.total_entries).to be(3)
    end
  end

  describe '#total_pages' do
    it "returns the total number of pages" do
      expect(subject.total_pages).to be(1)
    end
  end

  describe '#offset' do
    it "returns the offset" do
      expect(subject.offset).to be(80)
    end
  end

  describe '#empty?' do
    context "when there are results" do
      it "returns false" do
        expect(subject.empty?).to be_falsey
      end
    end

    context "when there are no results" do
      subject { Service::Client::ListResponse.new(20, empty_response, "results", name: "value") }

      it "returns true" do
        expect(subject.empty?).to be_truthy
      end
    end
  end

  describe '#==' do
    let(:other_search) { Service::Client::ListResponse.new(20, response, "results", name: "value") }

    context "when compared with another response" do
      it "returns true" do
        expect(subject == other_search).to be_truthy
      end
    end

    context "when compared with an array" do
      it "returns true" do
        expect(subject == other_search.to_a).to be_truthy
      end
    end

    context "when compared with nil" do
      it "returns false" do
        expect(subject == nil).to be_falsey
      end
    end

    context "when compared with something else" do
      it "returns false" do
        expect(subject == "stuff").to be_falsey
      end
    end
  end

  describe '#each' do
    it "iterates over the list of results" do
      subject.each do |result|
        expect(result).to be_a(Hash)
      end
    end
  end
end
