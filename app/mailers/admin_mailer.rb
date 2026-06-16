# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  def send_email
    @body_html = params[:body]
    mail(to: params[:to], subject: params[:subject])
  end
end
