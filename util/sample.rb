def weighted_sample(array)
  return nil if array.length == 0

  total_weight = array.inject(0.0) { |sum, obj| sum + obj[1] }
  rng = Random.new
  x = rng.rand(total_weight)
  choice = 0
  array.each_with_index do |obj, i|
    if obj[1] > x
      choice = i
      break
    else
      x -= obj[1]
    end
  end

  array.delete_at(choice)[0]
end

def weighted_samples(array, n)
  n.times.map do
    weighted_sample(array)
  end
end
