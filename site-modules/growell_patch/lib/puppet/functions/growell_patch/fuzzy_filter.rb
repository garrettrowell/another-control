Puppet::Functions.create_function(:'growell_patch::fuzzy_filter') do
  dispatch :fuzzy_filter do
    param 'Array', :input_arr
    param 'Array', :filter_arr
  end

  def fuzzy_filter(input_arr, filter_arr)
    output = []
    input_arr.each do |item|
      match_found = false
      filter_arr.each do |block_item|
        break if match_found
        match_found = true if item.match(Regexp.new(block_item))
      end
      output.push(item) unless match_found
    end
    output
  end
end
