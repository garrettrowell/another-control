Puppet::Functions.create_function(:'growell_patch::fuzzy_match') do
  dispatch :fuzzy_match do
    param 'Array', :input_arr
    param 'Array', :match_arr
  end

  def fuzzy_match(input_arr, match_arr)
    output = []
    input_arr.each do |item|
      match_found = false
      match_arr.each do |match_item|
        break if match_found
        match_found = true if item.match(Regexp.new(match_item))
      end
      output.push(item) if match_found
    end
    output
  end
end
