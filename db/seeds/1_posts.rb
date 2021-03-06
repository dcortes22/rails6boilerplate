# frozen_string_literal: true

p 'Creating Posts'

users = User.all

100.times do
  Post.create!(
    title: Faker::Quote.famous_last_words,
    publish_date: Faker::Date.between(from: 1.year.ago, to: Date.today),
    user: users.sample
  )
end
