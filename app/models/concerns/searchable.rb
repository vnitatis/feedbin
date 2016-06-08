module Searchable
  extend ActiveSupport::Concern

  included do
    include Elasticsearch::Model

    mapping _source: {enabled: false} do
      indexes :id,        index: :not_analyzed
      indexes :title,     analyzer: 'snowball'
      indexes :content,   analyzer: 'snowball'
      indexes :author,    analyzer: 'keyword'
      indexes :url,       analyzer: 'keyword'
      indexes :feed_id,   index: :not_analyzed, include_in_all: false
      indexes :published, type: 'date', include_in_all: false
      indexes :updated,   type: 'date', include_in_all: false
    end

    def self.scoped_search(params, user)
      params = build_search(params)
      options = {
        query: params[:query],
        sort: "desc",
        starred_ids: user.starred_entries.pluck(:entry_id),
        ids: [],
        not_ids: [],
        feed_ids: [],
      }

      # unless params[:load] == false
      #   search_options[:load] = { include: :feed }
      # end

      if params[:read] == false
        options[:ids].push(user.unread_entries.pluck(:entry_id))
      elsif params[:read] == true
        options[:not_ids].push(user.unread_entries.pluck(:entry_id))
      end

      if params[:starred] == true
        options[:ids].push(user.starred_entries.pluck(:entry_id))
      elsif params[:starred] == false
        options[:not_ids].push(user.starred_entries.pluck(:entry_id))
      end

      if params[:sort] && %w{desc asc}.include?(params[:sort])
        options[:sort] = params[:sort]
      end

      if params[:feed_ids].present?
        subscribed_ids = user.subscriptions.pluck(:feed_id)
        requested_ids = params[:feed_ids]
        options[:feed_ids] = (requested_ids & subscribed_ids)
      elsif params[:tag_id].present?
        options[:feed_ids] = user.taggings.where(tag_id: params[:tag_id]).pluck(:feed_id)
      else
        options[:feed_ids] = user.subscriptions.pluck(:feed_id)
      end

      if options[:ids].present?
        options[:ids] = options[:ids].inject(:&)
      end

      if options[:not_ids].present?
        options[:not_ids] = options[:ids].inject(:&)
      end

      build_query(options)
    end

    def self.build_query(options)
      Jbuilder.encode do |json|
        json.fields ["id"]
        json.sort [ {published: options[:sort]} ]

        if options[:query].present?
          json.simple_query_string do
            json.query options[:query]
            json.default_operator "AND"
          end
        end

        json.bool do
          json.should [
            {terms: {feed_ids: options[:feed_ids]}},
            {terms: {ids: options[:starred_ids]}}
          ]
          if options[:ids].present?
            json.must do
              json.terms do
                json.id options[:ids]
              end
            end
          end

          if options[:not_ids].present?
            json.must_not do
              json.terms do
                json.id options[:not_ids]
              end
            end
          end
        end
      end
    end

    def self.build_search(params)
      unread_regex = /(?<=\s|^)is:\s*unread(?=\s|$)/
      read_regex = /(?<=\s|^)is:\s*read(?=\s|$)/
      starred_regex = /(?<=\s|^)is:\s*starred(?=\s|$)/
      unstarred_regex = /(?<=\s|^)is:\s*unstarred(?=\s|$)/
      sort_regex = /(?<=\s|^)sort:\s*(asc|desc|relevance)(?=\s|$)/i
      tag_id_regex = /(?<=\s|^)tag_id:\s*([0-9]+)(?=\s|$)/

      if params[:query] =~ unread_regex
        params[:query] = params[:query].gsub(unread_regex, '')
        params[:read] = false
      elsif params[:query] =~ read_regex
        params[:query] = params[:query].gsub(read_regex, '')
        params[:read] = true
      end

      if params[:query] =~ starred_regex
        params[:query] = params[:query].gsub(starred_regex, '')
        params[:starred] = true
      elsif params[:query] =~ unstarred_regex
        params[:query] = params[:query].gsub(unstarred_regex, '')
        params[:starred] = false
      end

      if params[:query] =~ sort_regex
        params[:sort] = params[:query].match(sort_regex)[1].downcase
        params[:query] = params[:query].gsub(sort_regex, '')
      end

      if params[:query] =~ tag_id_regex
        params[:tag_id] = params[:query].match(tag_id_regex)[1].downcase
        params[:query] = params[:query].gsub(tag_id_regex, '')
      end

      params
    end

  end
end