json.response_code @response_code
json.response_message @response_message
json.data do
  json.array! @posts
end
