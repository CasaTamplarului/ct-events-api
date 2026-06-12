# frozen_string_literal: true

module Api
  module V1
    module Scan
      class OrdersController < ActionController::API
        include Authenticatable
        include ScanSerialisable
        include LocaleSetter

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }
        before_action :set_locale
        before_action :set_order
        before_action :prevent_self_checkin!, only: :update

        def show
          render json: serialise_order(@order)
        end

        def update
          update_params = params.permit(attendees: %i[id checked_in payment_status])

          if update_params[:attendees].blank?
            return render json: { error: 'Nothing to update' }, status: :unprocessable_content
          end

          error = update_attendee_checkins(update_params)
          return render json: error, status: :unprocessable_content if error

          render json: serialise_order(@order)
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: I18n.t('errors.not_found') }, status: :not_found unless @order
          end

          def prevent_self_checkin!
            return unless current_user.attendees.exists?(order: @order)

            render json: { error: I18n.t('scan.errors.self_checkin_forbidden') }, status: :forbidden
          end

          def update_attendee_checkins(update_params) # rubocop:disable Metrics/CyclomaticComplexity
            order_attendees = @order.attendees.includes(:ticket).index_by(&:id)
            Array(update_params[:attendees]).each do |entry|
              attendee = order_attendees[entry[:id].to_i]
              next unless attendee

              attrs = {}

              if entry.key?(:checked_in)
                if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
                  if date_restricted?(attendee.ticket)
                    return { error: I18n.t('scan.errors.invalid_checkin_date') }
                  end

                  attrs.merge!(checked_in: true, checked_in_at: Time.current,
                               checked_in_by_user_id: current_user.id)
                  attrs[:payment_status] = :payment_pending if attendee.attendee_cancelled? || attendee.refunded?
                else
                  attrs.merge!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
                end
              end

              if entry[:payment_status].present? && Attendee.payment_statuses.key?(entry[:payment_status].to_s)
                attrs[:payment_status] = entry[:payment_status]
              end

              attendee.update!(attrs) if attrs.any?
            end
            nil
          end

          def date_restricted?(ticket)
            return false unless ticket
            return false if ticket.valid_from.nil? && ticket.valid_to.nil?

            today = Time.current.in_time_zone('Europe/Bucharest').to_date
            (ticket.valid_from && today < ticket.valid_from) ||
              (ticket.valid_to  && today > ticket.valid_to)
          end
      end
    end
  end
end
