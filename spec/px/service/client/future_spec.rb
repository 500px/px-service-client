require 'spec_helper'

describe Px::Service::Client::Future do
  subject { Px::Service::Client::Future.new(String) }
  let(:value) { "value" }

  describe '#complete' do
    it "calls any pending methods on the response" do
      expect(value).to receive(:size)
      called = false
      subject

      Fiber.new do
        subject.size
        called = true
      end.resume

      Fiber.new do
        subject.complete(value)
      end.resume

      expect(called).to eq(true)
    end
  end

  describe '#completed?' do
    context "when the future is completed" do
      it "returns true" do
        Fiber.new do
          subject.complete(value)
        end.resume

        expect(subject.completed?).to eq(true)
      end
    end

    context "when the future is not completed" do
      it "returns false" do
        expect(subject.completed?).to eq(false)
      end
    end
  end

  describe '#value' do
    context "when the future is not complete" do
      it "does not call the method on the value" do
        called = false
        Fiber.new do
          subject.size
          called = true
        end.resume

        expect(called).to eq(false)
      end
    end

    context "when the future is already complete" do
      it "returns the value" do
        subject.complete(value)
        expect(subject.value).to eq(value)
      end
    end

    context "when the value is an exception" do
      it "returns the exception" do
        Fiber.new do
          expect(subject.value).to be_a(ArgumentError)
        end.resume

        Fiber.new do
          subject.complete(ArgumentError.new("Error"))
        end.resume
      end
    end

    context "when the method returns a value" do
      it "returns the value" do
        Fiber.new do
          expect(subject.value).to eq(value)
        end.resume

        Fiber.new do
          subject.complete(value)
        end.resume
      end
    end
  end

  describe '#method_missing' do
    context "when the future is already complete" do
      context "when the method raised an exception" do
        before :each do
          subject.complete(nil)
        end

        it "raises the exception" do
          Fiber.new do
            expect {
              subject.size
            }.to raise_error(NoMethodError)
          end.resume
        end
      end

      context "when the method returns a value" do
        before :each do
          subject.complete(value)
        end

        it "returns the value" do
          Fiber.new do
            expect(subject.size).to eq(value.size)
          end.resume
        end
      end
    end

    context "when the future is not complete" do
      it "does not call the method on the value" do
        expect(value).not_to receive(:size)

        Fiber.new do
          subject.size
        end.resume
      end

      context "when the method raised an exception" do
        it "raises the exception" do
          Fiber.new do
            expect {
              subject.size
            }.to raise_error(NoMethodError)
          end.resume

          Fiber.new do
            subject.complete(nil)
          end.resume
        end
      end

      context "when the method returns a value" do
        it "returns the value" do
          Fiber.new do
            expect(subject.size).to eq(value.size)
          end.resume

          Fiber.new do
            subject.complete(value)
          end.resume
        end
      end
    end
  end
end
