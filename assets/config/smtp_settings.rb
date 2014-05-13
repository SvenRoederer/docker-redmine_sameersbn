if Rails.env.production?
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = {
    :address              => "{{SMTP_HOST}}",
    :port                 => {{SMTP_PORT}},
    :domain               => "{{SMTP_DOMAIN}}",
    :user_name            => "{{SMTP_USER}}",
    :password             => "{{SMTP_PASS}}",
    :authentication       => "{{SMTP_AUTHENTICATION}}",
    :enable_starttls_auto => {{SMTP_STARTTLS}}
  }
end
