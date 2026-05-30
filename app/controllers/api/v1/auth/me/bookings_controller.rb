# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class BookingsController < ActionController::API
          include Authenticatable
          include LocaleSetter

          before_action :authenticate_user!
          before_action :set_locale

          def upcoming
            orders = orders_for_user_scoped_to(
              where_clause: 'events.start_date > ?',
              sort: 'events.start_date ASC'
            )
            render json: serialise_orders(orders)
          end

          def past
            orders = orders_for_user_scoped_to(
              where_clause: 'events.end_date <= ?',
              sort: 'events.start_date DESC'
            )
            render json: serialise_orders(orders)
          end

          private

            def orders_for_user_scoped_to(where_clause:, sort:)
              # Collect ordered, distinct order IDs via attendees (avoids DISTINCT + ORDER BY conflict)
              ordered_order_ids =
                Attendee.joins(:event)
                        .where(user_id: current_user.id)
                        .where(where_clause, Time.current)
                        .where(events: { status: Event.statuses[:live] })
                        .order(sort)
                        .pluck(:order_id)
                        .uniq

              # Load and return orders preserving the correct sort order
              orders_by_id = Order.where(id: ordered_order_ids).index_by(&:id)
              ordered_order_ids.filter_map { |id| orders_by_id[id] }
            end

            def serialise_orders(orders)
              return [] if orders.empty?

              order_ids = orders.map(&:id)
              attendees_by_order = Attendee
                                   .where(order_id: order_ids, user_id: current_user.id)
                                   .includes({ ticket: :tickets_translations }, { event: :events_translations })
                                   .group_by(&:order_id)

              orders.filter_map { |order| serialise_order(order, attendees_by_order[order.id] || []) }
            end

            def serialise_order(order, attendees)
              return nil if attendees.empty?

              event = attendees.first.event
              lang  = current_user.language || 'ro-RO'

              {
                order_reference: order.order_reference,
                payment_status: attendees.first.payment_status,
                event: serialise_event(event, lang),
                attendees: attendees.map { |a| serialise_attendee(a, lang) }
              }
            end

            def serialise_event(event, lang)
              name = event.events_translations.find { |t| t.languages_code == lang }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name
              {
                name: name,
                slug: event.slug,
                start_date: event.start_date,
                end_date: event.end_date,
                location_name: event.location_name,
                address: event.address
              }
            end

            def serialise_attendee(attendee, lang)
              {
                first_name: attendee.first_name,
                last_name: attendee.last_name,
                ticket_name: ticket_name_for(attendee, lang),
                dietary_preference: attendee.dietary_preference
              }
            end

            def ticket_name_for(attendee, lang)
              ticket = attendee.ticket
              return nil if ticket.nil?

              translation_name(ticket.tickets_translations, lang)
            end

            def translation_name(translations, lang)
              translations.find { |t| t.languages_code == lang }&.name ||
                translations.find { |t| t.languages_code == 'ro-RO' }&.name
            end
        end
      end
    end
  end
end
