require "compiler/crystal/loader"
require "../src/candiru"

begin
  loader = Crystal::Loader.new([Dir.current])
  loader.load_library "sum"

  # Declare:

  point_struct = Candiru::StructScaffolding[Float64, Float64]
  rect_struct = Candiru::StructScaffolding[point_struct, point_struct]
  rect_list_struct = Candiru::StructScaffolding.new
  rect_list_struct << rect_struct
  rect_list_struct << rect_list_struct

  point_new_handle = loader.find_symbol("Point_New")
  point_new = Candiru::Fn.new(point_new_handle, [Float64, Float64], point_struct)

  point_add_handle = loader.find_symbol("Point_Add")
  point_add = Candiru::Fn.new(point_add_handle, [point_struct, point_struct], point_struct)

  point_see_handle = loader.find_symbol("Point_See")
  point_see = Candiru::Fn.new(point_see_handle, [point_struct])

  point_free_handle = loader.find_symbol("Point_Free")
  point_free = Candiru::Fn.new(point_free_handle, [point_struct])

  rect_new_handle = loader.find_symbol("Rect_New")
  rect_new = Candiru::Fn.new(rect_new_handle, [point_struct, point_struct], rect_struct)

  rect_see_handle = loader.find_symbol("Rect_See")
  rect_see = Candiru::Fn.new(rect_see_handle, [rect_struct])

  rect_free_handle = loader.find_symbol("Rect_Free")
  rect_free = Candiru::Fn.new(rect_free_handle, [rect_struct])

  rect_list_new_handle = loader.find_symbol("RectList_New")
  rect_list_new = Candiru::Fn.new(rect_list_new_handle, returns: rect_list_struct)

  rect_list_append_handle = loader.find_symbol("RectList_Append")
  rect_list_append = Candiru::Fn.new(rect_list_append_handle, [rect_list_struct, rect_struct])

  rect_list_free_handle = loader.find_symbol("RectList_Free")
  rect_list_free = Candiru::Fn.new(rect_list_free_handle, [rect_list_struct])

  # Use:

  # WARNING: Point_New uses C malloc, you'll need to free these
  # yourself! StructScaffolding#new uses GCd malloc.
  a = point_new.call(12_f64, 34_f64)
  b = point_new.call(56_f64, 78_f64)
  c = point_add.call(a, b)
  d = point_new.call(1f64, 2f64)

  point_see.call(a)
  point_see.call(b)
  point_see.call(c)
  point_see.call(d)

  # Inspect from Crystal, behaves like tuple.
  puts d.as(Candiru::StructInstance)[0] # 12.0
  puts d.as(Candiru::StructInstance)[1] # 34.0

  # Create two rects:
  rect1 = rect_new.call(a, b)
  rect2 = rect_new.call(c, d)

  rect_see.call(rect1)
  rect_see.call(rect2)

  # Inspect from Crystal:
  rect1.as(Candiru::StructInstance).each do |field|
    point = field.as(Candiru::StructInstance)
    puts "X from Crystal! = #{point[0]}"
    puts "Y from Crystal! = #{point[1]}"
  end

  # Create a rect list from them:
  rect_list = rect_list_new.call

  rect_list_append.call(rect_list, rect1)
  rect_list_append.call(rect_list, rect2)

  # Iterate from Crystal:
  rect, nxt = rect_list.as(Candiru::StructInstance)
  rects = [rect] of Candiru::IValueInstanceType

  until nxt.nil?
    rect, nxt = nxt.as(Candiru::StructInstance)
    rects << rect
  end

  rects.each do |rect|
    next if rect.nil? # BUG
    rect_see.call(rect)
  end

  rect_list_free.call(rect_list)
ensure
  loader.try &.close_all
end
