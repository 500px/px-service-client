require 'will_paginate/collection'

module Service::Client
  ##
  # This class implements the methods necessary to be compatible with WillPaginate and Enumerable
  class ListResponse
    include WillPaginate::CollectionMethods
    include Enumerable

    attr_reader :response, :per_page

    DEFAULT_PER_PAGE = 20

    def initialize(page_size, response, results_key, options = {})
      @response = response
      @results_key = results_key
      @options = options
      @per_page = page_size || DEFAULT_PER_PAGE
    end

    ##
    # Get the current page
    def current_page
      response["current_page"]
    end

    def offset
      (current_page - 1) * per_page
    end

    def total_entries
      response["total_items"]
    end
    alias_method :total, :total_entries

    def total_pages
      response["total_pages"]
    end

    def results
      response[@results_key]
    end

    def raw_results
      response[@results_key]
    end

    ##
    # Support Enumerable
    def each(&block)
      results.each(&block)
    end

    ##
    # Allow comparisons with arrays e.g. in Rspec to succeed
    def ==(other)
      if other.class == self.class
        other.results == self.results
      elsif other.class <= Array
        other == self.results
      else
        false
      end
    end
    alias_method :eql?, :==

    def empty?
      results.empty?
    end

    def method_missing(method_name, *arguments, &block)
      results.send(method_name, *arguments, &block)
    end

    def respond_to?(method_name, include_private = false)
      results.respond_to?(method_name, include_private)
    end

  end
end
