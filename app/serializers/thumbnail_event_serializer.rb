# frozen_string_literal: true

class ThumbnailEventSerializer < ApplicationSerializer
  attributes :start_date, :end_date

  attribute :name do |object|
    object.translations(params[:languages_code]).name
  end

  attribute :tag_line do |object|
    object.translations(params[:languages_code]).tag_line
  end

  attribute :description do |object|
    object.translations(params[:languages_code]).description
  end

  attribute :fully_booked, &:fully_booked?

  attribute :starts_from do |object|
    params[:show_price] == false ? nil : object.starts_from
  end

  attribute :tickets do |object|
    return nil unless object.tickets

    TicketSerializer.new(object.tickets,
                         params: { languages_code: params[:languages_code], show_price: params[:show_price] })
  end

  attribute :slug, &:slug
  attributes :address, :location_name, :embed_url

  attribute :hero_image do |object|
    ApplicationSerializer.asset_url(object.hero_image)
  end

  attribute :hero_portrait do |object|
    ApplicationSerializer.asset_url(object.hero_portrait)
  end

  attribute :gallery_preview do |object|
    ApplicationSerializer.asset_url(object.event_gallery_items.first&.directus_files_id)
  end
end
