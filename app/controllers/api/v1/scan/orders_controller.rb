# frozen_string_literal: true

module Api
  module V1
    module Scan
      class OrdersController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_check_in_attendees) }
        before_action :set_order

        def show
          render json: serialise_order
        end

        def update
          update_params = params.permit(:payment_status, attendees: %i[id checked_in])

          if update_params[:payment_status].blank? && update_params[:attendees].blank?
            return render json: { error: 'Nothing to update' }, status: :unprocessable_content
          end

          if update_params[:payment_status].present? &&
             !Order.payment_statuses.key?(update_params[:payment_status].to_s)
            return render json: { error: "Invalid payment_status: #{update_params[:payment_status]}" },
                          status: :unprocessable_content
          end

          ActiveRecord::Base.transaction do
            @order.update!(payment_status: update_params[:payment_status]) if update_params[:payment_status].present?
            update_attendee_checkins(update_params)
          end

          render json: serialise_order
        end

        private

          def set_order
            @order = Order.find_by(order_reference: params[:order_reference])
            render json: { error: 'Not found' }, status: :not_found unless @order
          end

          def update_attendee_checkins(update_params)
            return if update_params[:attendees].blank?

            order_attendees = @order.attendees.index_by(&:id)
            Array(update_params[:attendees]).each do |entry|
              attendee = order_attendees[entry[:id].to_i]
              next unless attendee

              if ActiveModel::Type::Boolean.new.cast(entry[:checked_in])
                attendee.update!(checked_in: true, checked_in_at: Time.current,
                                 checked_in_by_user_id: current_user.id)
              else
                attendee.update!(checked_in: false, checked_in_at: nil, checked_in_by_user_id: nil)
              end
            end
          end

          def serialise_order
            attendees = @order.attendees
                              .includes(:checked_in_by, ticket: :tickets_translations)
                              .order(:id)
            {
              order_reference: @order.order_reference,
              payment_status: @order.payment_status,
              attendees: attendees.map { |a| serialise_attendee(a) }
            }
          end

          def serialise_attendee(attendee)
            by = attendee.checked_in_by
            {
              id: attendee.id,
              first_name: attendee.first_name,
              last_name: attendee.last_name,
              email_address: attendee.email_address,
              ticket_name: attendee.ticket
                           &.tickets_translations
                           &.find { |t| t.languages_code == 'ro-RO' }
                           &.name,
              checked_in: attendee.checked_in,
              checked_in_at: attendee.checked_in_at,
              checked_in_by: by ? "#{by.first_name} #{by.last_name}".strip : nil
            }
          end
      end
    end
  end
end
