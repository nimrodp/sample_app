FactoryGirl.define do
  factory :user do
    name     "Nimrod Popper"
    email    "nimrod@example.com"
    password "foobar"
    password_confirmation "foobar"
  end
end