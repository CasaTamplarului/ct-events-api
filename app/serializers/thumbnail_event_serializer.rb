# frozen_string_literal: true

class ThumbnailEventSerializer < ApplicationSerializer
  attributes :start_date, :end_date

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :fully_booked, &:fully_booked?
end
