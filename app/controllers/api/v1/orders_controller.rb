# frozen_string_literal: true

module Api
  module V1
    class OrdersController < ActionController::API
      PERMITTED_ATTENDEE_FIELDS = %w[first_name last_name email_address phone_number dietary_preference church_name
                                     city].freeze

      before_action :set_locale
      before_action :set_current_user

      def create
        items = params[:items]
        return render json: { error: t('orders.errors.items_blank') }, status: :bad_request if items.blank?

        resolved = resolve_items(items)
        return if performed?

        check_capacity(resolved)
        return if performed?

        order = persist_order(resolved)
        SendgridService.send_booking_confirmation(order: order, language: params[:languages_code])
        render json: { order_reference: order.order_reference }, status: :created
      rescue StandardError
        render json: { error: t('orders.errors.internal_error') }, status: :internal_server_error
      end

      private

        def set_current_user
          token = request.headers['Authorization']&.split&.last
          return if token.blank?

          user_id = JwtService.decode(token)
          @current_user = User.active.find_by(id: user_id)
        rescue JWT::DecodeError
          nil
        end

        def resolve_items(items)
          items.each_with_object([]) do |item, result|
            event = Event.find_by(slug: item[:event_slug])
            unless event
              render json: { error: t('orders.errors.unknown_event', slug: item[:event_slug]) }, status: :bad_request
              break
            end

            ticket = event.tickets
                          .joins(:tickets_translations)
                          .where(tickets_translations: { name: item[:ticket_name],
                                                         languages_code: params[:languages_code] })
                          .first
            unless ticket
              render json: { error: t('orders.errors.unknown_ticket', name: item[:ticket_name]) }, status: :bad_request
              break
            end

            result << { event: event, ticket: ticket, attendee_attrs: attendee_attrs(item[:attendee]) }
          end
        end

        def check_capacity(resolved)
          resolved.group_by { |i| i[:event] }.each do |event, items_for_event|
            next unless event.max_number_of_people

            if event.attendees.count + items_for_event.size > event.max_number_of_people
              render json: { error: t('orders.errors.fully_booked') }, status: :conflict
              break
            end
          end
        end

        def persist_order(resolved)
          order = nil
          ActiveRecord::Base.transaction do
            order = Order.create!(user: @current_user)
            resolved.each do |item|
              email = item[:attendee_attrs][:email_address]
              linked_user = email.present? ? User.active.find_by('LOWER(email) = LOWER(?)', email) : nil
              order.attendees.create!(
                event: item[:event],
                ticket: item[:ticket],
                user: linked_user,
                **item[:attendee_attrs]
              )
            end
          end
          order
        end

        def attendee_attrs(raw)
          raw.to_unsafe_h.slice(*PERMITTED_ATTENDEE_FIELDS).symbolize_keys
        end

        def set_locale
          lang = params[:languages_code].to_s.split('-').first.to_sym
          I18n.locale = I18n.available_locales.include?(lang) ? lang : I18n.default_locale
        end

        def t(key, **)
          I18n.t(key, **)
        end
    end
  end
end
