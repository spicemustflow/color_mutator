extends Control

# --- Enum для выбора метода сдвига ---
enum ShiftMethod { RGB, HSV }

# --- Параметры генерации ---
var current_brightness_limit: float = 150.0
var current_shift_method: ShiftMethod = ShiftMethod.HSV # По умолчанию
# Параметры RGB сдвига
var current_rgb_shift_amount: int = 50
# Параметры HSV сдвига (диапазоны +/-)
var current_hsv_hue_shift: float = 0.05
var current_hsv_sat_shift: float = 0.15
var current_hsv_val_shift: float = 0.1

const _MAX_MUTATION_ATTEMPTS := 500 # Макс. попыток найти подходящий цвет

# --- Настройки текста на плашках ---
var show_palette_text := false
var palette_text_format := "%hex%"
var palette_text_size := 32
var palette_text_color_hex := "ffffff"
var palette_text_color := Color.WHITE

# --- Функции генерации цвета ---
# Применяет RGB сдвиг к цвету (int)
func _apply_rgb_shift(base_color_int: int) -> Color:
	var r: int = (base_color_int >> 16) & 0xFF; var g: int = (base_color_int >> 8) & 0xFF; var b: int = base_color_int & 0xFF
	r = clamp(r + randi_range(-current_rgb_shift_amount, current_rgb_shift_amount), 0, 255)
	g = clamp(g + randi_range(-current_rgb_shift_amount, current_rgb_shift_amount), 0, 255)
	b = clamp(b + randi_range(-current_rgb_shift_amount, current_rgb_shift_amount), 0, 255)
	return Color(r / 255.0, g / 255.0, b / 255.0)

# Применяет HSV сдвиг к цвету (Color)
func _apply_hsv_shift(base_color: Color) -> Color:
	var h := base_color.h; var s_orig := base_color.s; var v := base_color.v # Сохраним оригинальный s
	var s_new : float

	# Применяем сдвиги HSV
	h = fposmod(h + randf_range(-current_hsv_hue_shift, current_hsv_hue_shift), 1.0)

	var sat_shift = randf_range(-current_hsv_sat_shift, current_hsv_sat_shift)
	s_new = clamp(s_orig + sat_shift, 0.0, 1.0)

	v = clamp(v + randf_range(-current_hsv_val_shift, current_hsv_val_shift), 0.0, 1.0)

	return Color.from_hsv(h, s_new, v) # Используем s_new

func get_brightness(color: Color) -> float:
	return 0.2126 * color.r8 + 0.7152 * color.g8 + 0.0722 * color.b8

# --- Ссылки на UI элементы ---
var color_input_label: Label
var color_input: LineEdit
# Настройки сдвига
var shift_settings_hbox: HBoxContainer
var shift_method_optionbutton: OptionButton
# Элементы RGB
var rgb_shift_amount_label: Label
var rgb_shift_amount_spinbox: SpinBox
# Элементы HSV
var hsv_hue_label: Label
var hsv_hue_spinbox: SpinBox
var hsv_sat_label: Label
var hsv_sat_spinbox: SpinBox
var hsv_val_label: Label
var hsv_val_spinbox: SpinBox
# Общий параметр
var brightness_limit_label: Label
var brightness_limit_spinbox: SpinBox
var mutate_button: Button
var status_label: Label
# Настройки текста
var text_settings_hbox: HBoxContainer
var show_text_checkbox: CheckBox
var palette_text_input: LineEdit
var palette_text_size_spinbox: SpinBox
var palette_text_color_label: Label
var palette_text_color_input: LineEdit
# Остальные
var original_palette_label: Label
var palette_display: HBoxContainer
var mutated_palette_label: Label
var mutated_palette_display: HBoxContainer
var output_colors_label: Label
var mutated_colors_text_grid: GridContainer

# --- Хранилище цветов ---
var current_base_colors_int: Array[int] = []
var last_mutated_colors: Array[Color] = []

func _ready() -> void:
	# --- Минимальный размер окна ---
	#DisplayServer.window_set_min_size(Vector2i(1280, 800))

	# --- Базовая структура: MarginContainer -> VBoxContainer ---
	var margin_container = MarginContainer.new(); margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin_size = 15; margin_container.add_theme_constant_override("margin_left", margin_size); margin_container.add_theme_constant_override("margin_top", margin_size); margin_container.add_theme_constant_override("margin_right", margin_size); margin_container.add_theme_constant_override("margin_bottom", margin_size)
	add_child(margin_container)
	var main_vbox = VBoxContainer.new(); margin_container.add_child(main_vbox); main_vbox.add_theme_constant_override("separation", 8)

	# --- Создаем UI элементы ВНУТРИ main_vbox ---

	# Поле ввода Hex
	color_input_label = Label.new(); color_input_label.text = "Input Hex Colors (0xRRGGBB or RRGGBB), comma-separated:"; main_vbox.add_child(color_input_label)
	color_input = LineEdit.new(); color_input.placeholder_text = "e.g., 0x9b5de5, f15bb5"; color_input.text = "0x264653, 0x2a9d8f, 0xe9c46a, 0xf4a261, 0xe76f51"
	color_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; main_vbox.add_child(color_input)

	# --- Настройки Сдвига (ОБЪЕДИНЕННЫЙ HBox) ---
	shift_settings_hbox = HBoxContainer.new(); shift_settings_hbox.alignment = BoxContainer.ALIGNMENT_CENTER; shift_settings_hbox.add_theme_constant_override("separation", 10)
	var method_label = Label.new(); method_label.text = "Shift Method:"; shift_settings_hbox.add_child(method_label)
	shift_method_optionbutton = OptionButton.new(); shift_method_optionbutton.add_item("RGB", ShiftMethod.RGB); shift_method_optionbutton.add_item("HSV", ShiftMethod.HSV)
	shift_method_optionbutton.select(current_shift_method); shift_method_optionbutton.item_selected.connect(_on_shift_method_selected)
	shift_settings_hbox.add_child(shift_method_optionbutton)

	# Параметры RGB
	rgb_shift_amount_label = Label.new(); rgb_shift_amount_label.text = " Amount:"; shift_settings_hbox.add_child(rgb_shift_amount_label)
	rgb_shift_amount_spinbox = SpinBox.new(); rgb_shift_amount_spinbox.min_value = 0; rgb_shift_amount_spinbox.max_value = 128; rgb_shift_amount_spinbox.step = 1
	rgb_shift_amount_spinbox.value = current_rgb_shift_amount; rgb_shift_amount_spinbox.custom_minimum_size.x = 60
	rgb_shift_amount_spinbox.value_changed.connect(_on_rgb_shift_amount_changed)
	# --- ТУЛТИП для RGB Amount ---
	rgb_shift_amount_spinbox.tooltip_text = "Max +/- random shift applied to each R,G,B channel (0-255)."
	shift_settings_hbox.add_child(rgb_shift_amount_spinbox)

	# Параметры HSV
	hsv_hue_label = Label.new(); hsv_hue_label.text = " Hue (+/-):"; shift_settings_hbox.add_child(hsv_hue_label)
	hsv_hue_spinbox = SpinBox.new(); hsv_hue_spinbox.min_value = 0.0; hsv_hue_spinbox.max_value = 0.5; hsv_hue_spinbox.step = 0.01; hsv_hue_spinbox.allow_greater = true
	hsv_hue_spinbox.value = current_hsv_hue_shift; hsv_hue_spinbox.custom_minimum_size.x = 60
	hsv_hue_spinbox.value_changed.connect(_on_hsv_setting_changed)
	# --- ТУЛТИП для HSV Hue ---
	hsv_hue_spinbox.tooltip_text = "Max +/- random shift applied to Hue (0.0-1.0).\nValue * 360 = degrees (e.g., %.2f = %d°)" % [current_hsv_hue_shift, int(current_hsv_hue_shift * 360.0)]
	shift_settings_hbox.add_child(hsv_hue_spinbox)

	hsv_sat_label = Label.new(); hsv_sat_label.text = " Sat (+/-):"; shift_settings_hbox.add_child(hsv_sat_label)
	hsv_sat_spinbox = SpinBox.new(); hsv_sat_spinbox.min_value = 0.0; hsv_sat_spinbox.max_value = 1.0; hsv_sat_spinbox.step = 0.01; hsv_sat_spinbox.allow_greater = true
	hsv_sat_spinbox.value = current_hsv_sat_shift; hsv_sat_spinbox.custom_minimum_size.x = 60
	hsv_sat_spinbox.value_changed.connect(_on_hsv_setting_changed)
	# --- ТУЛТИП для HSV Saturation ---
	hsv_sat_spinbox.tooltip_text = "Max +/- random shift applied to Saturation (0.0-1.0).\nValue * 100 = percent (e.g., %.2f = %d%%)" % [current_hsv_sat_shift, int(current_hsv_sat_shift * 100.0)]
	shift_settings_hbox.add_child(hsv_sat_spinbox)

	hsv_val_label = Label.new(); hsv_val_label.text = " Val (+/-):"; shift_settings_hbox.add_child(hsv_val_label)
	hsv_val_spinbox = SpinBox.new(); hsv_val_spinbox.min_value = 0.0; hsv_val_spinbox.max_value = 1.0; hsv_val_spinbox.step = 0.01; hsv_val_spinbox.allow_greater = true
	hsv_val_spinbox.value = current_hsv_val_shift; hsv_val_spinbox.custom_minimum_size.x = 60
	hsv_val_spinbox.value_changed.connect(_on_hsv_setting_changed)
	# --- ТУЛТИП для HSV Value ---
	hsv_val_spinbox.tooltip_text = "Max +/- random shift applied to Value (0.0-1.0).\nValue * 100 = percent (e.g., %.2f = %d%%)" % [current_hsv_val_shift, int(current_hsv_val_shift * 100.0)]
	shift_settings_hbox.add_child(hsv_val_spinbox)

	main_vbox.add_child(shift_settings_hbox) # Добавляем общий HBox в VBox

	# Общая настройка яркости
	var brightness_hbox = HBoxContainer.new(); brightness_hbox.alignment = BoxContainer.ALIGNMENT_CENTER; brightness_hbox.add_theme_constant_override("separation", 10)
	brightness_limit_label = Label.new(); brightness_limit_label.text = "Max Brightness Limit:"; brightness_hbox.add_child(brightness_limit_label)
	brightness_limit_spinbox = SpinBox.new(); brightness_limit_spinbox.min_value = 0; brightness_limit_spinbox.max_value = 255; brightness_limit_spinbox.step = 1
	brightness_limit_spinbox.value = current_brightness_limit; brightness_limit_spinbox.custom_minimum_size.x = 80
	brightness_limit_spinbox.value_changed.connect(_on_brightness_limit_changed)
	# --- ТУЛТИП для Max Brightness ---
	brightness_limit_spinbox.tooltip_text = "Maximum allowed perceived brightness (BT.709 luma formula, range 0-255)."
	brightness_hbox.add_child(brightness_limit_spinbox)
	main_vbox.add_child(brightness_hbox)

	# Настройки текста на плашках
	text_settings_hbox = HBoxContainer.new(); text_settings_hbox.alignment = BoxContainer.ALIGNMENT_CENTER; text_settings_hbox.add_theme_constant_override("separation", 10)
	show_text_checkbox = CheckBox.new(); show_text_checkbox.text = "Show Text on Palettes"; show_text_checkbox.button_pressed = show_palette_text
	show_text_checkbox.toggled.connect(_on_palette_text_setting_changed); text_settings_hbox.add_child(show_text_checkbox)
	var text_label = Label.new(); text_label.text = " Format:"; text_settings_hbox.add_child(text_label)
	palette_text_input = LineEdit.new(); palette_text_input.text = palette_text_format; palette_text_input.placeholder_text = "%hex%, %rgb%, %r%, etc."
	palette_text_input.custom_minimum_size.x = 150; palette_text_input.text_changed.connect(_on_palette_text_setting_changed); text_settings_hbox.add_child(palette_text_input)
	var size_label = Label.new(); size_label.text = " Size:"; text_settings_hbox.add_child(size_label)
	palette_text_size_spinbox = SpinBox.new(); palette_text_size_spinbox.min_value = 6; palette_text_size_spinbox.max_value = 48; palette_text_size_spinbox.step = 1
	palette_text_size_spinbox.value = palette_text_size; palette_text_size_spinbox.custom_minimum_size.x = 60
	palette_text_size_spinbox.value_changed.connect(_on_palette_text_setting_changed); text_settings_hbox.add_child(palette_text_size_spinbox)
	palette_text_color_label = Label.new(); palette_text_color_label.text = " Color (Hex):"; text_settings_hbox.add_child(palette_text_color_label)
	palette_text_color_input = LineEdit.new(); palette_text_color_input.text = palette_text_color_hex; palette_text_color_input.placeholder_text = "RRGGBB"
	palette_text_color_input.max_length = 6; palette_text_color_input.custom_minimum_size.x = 80
	palette_text_color_input.text_changed.connect(_on_palette_text_setting_changed); text_settings_hbox.add_child(palette_text_color_input)
	main_vbox.add_child(text_settings_hbox)

	# Остальное UI
	mutate_button = Button.new(); mutate_button.text = "Mutate"; mutate_button.pressed.connect(_on_mutate_button_pressed); main_vbox.add_child(mutate_button)
	status_label = Label.new(); status_label.autowrap_mode = TextServer.AUTOWRAP_WORD; main_vbox.add_child(status_label)
	original_palette_label = Label.new(); original_palette_label.text = "Original Palette:"; main_vbox.add_child(original_palette_label)
	palette_display = HBoxContainer.new(); palette_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL; palette_display.size_flags_vertical = Control.SIZE_EXPAND_FILL; palette_display.custom_minimum_size.y = 50; palette_display.add_theme_constant_override("separation", 5); main_vbox.add_child(palette_display)
	mutated_palette_label = Label.new(); mutated_palette_label.text = "Mutated Palette:"; main_vbox.add_child(mutated_palette_label)
	mutated_palette_display = HBoxContainer.new(); mutated_palette_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mutated_palette_display.size_flags_vertical = Control.SIZE_EXPAND_FILL; mutated_palette_display.custom_minimum_size.y = 50; mutated_palette_display.add_theme_constant_override("separation", 5); main_vbox.add_child(mutated_palette_display)
	output_colors_label = Label.new(); output_colors_label.text = "Copy Mutated Colors (Formats: 0xHex, Hex, R,G,B [0.0-1.0]):"; main_vbox.add_child(output_colors_label)
	mutated_colors_text_grid = GridContainer.new(); mutated_colors_text_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mutated_colors_text_grid.add_theme_constant_override("v_separation", 2); main_vbox.add_child(mutated_colors_text_grid)

	# --- Первичная обработка ---
	_update_shift_settings_visibility()
	_update_initial_settings()
	if not _parse_and_display_input(): status_label.text = "Error in default input value."

func _update_initial_settings(): _on_palette_text_setting_changed()

# --- Обработчики изменения настроек ---
func _on_rgb_shift_amount_changed(value: float) -> void: current_rgb_shift_amount = int(value)
func _on_hsv_setting_changed(value: float) -> void: # Общий для HSV
	current_hsv_hue_shift = hsv_hue_spinbox.value; current_hsv_sat_shift = hsv_sat_spinbox.value; current_hsv_val_shift = hsv_val_spinbox.value
func _on_brightness_limit_changed(value: float) -> void: current_brightness_limit = value
func _on_palette_text_setting_changed(value = null) -> void:
	show_palette_text = show_text_checkbox.button_pressed; palette_text_format = palette_text_input.text
	palette_text_size = int(palette_text_size_spinbox.value)
	var hex_color_text = palette_text_color_input.text.strip_edges()
	if hex_color_text.length() == 6 and hex_color_text.is_valid_hex_number(false):
		palette_text_color_hex = hex_color_text; palette_text_color = Color.from_string(palette_text_color_hex, Color.WHITE)
	else: palette_text_color = Color.from_string(palette_text_color_hex, Color.WHITE)
	_redraw_palettes_with_text()

func _on_shift_method_selected(index: int) -> void:
	var selected_id : int = shift_method_optionbutton.get_item_id(index)
	# Используем match для явного присвоения значения enum
	match selected_id:
		ShiftMethod.RGB: # Сравниваем int с enum значением (неявно преобразуется)
			current_shift_method = ShiftMethod.RGB # Присваиваем enum значение
		ShiftMethod.HSV:
			current_shift_method = ShiftMethod.HSV
		_:
			# Этот случай не должен произойти, если OptionButton настроен правильно
			printerr("Error: Unknown shift method ID selected: ", selected_id)
			current_shift_method = ShiftMethod.HSV # Возврат к дефолтному на всякий случай
	_update_shift_settings_visibility()

# Функция для скрытия/показа настроек сдвига
func _update_shift_settings_visibility() -> void:
	var is_rgb = (current_shift_method == ShiftMethod.RGB); var is_hsv = (current_shift_method == ShiftMethod.HSV)
	rgb_shift_amount_label.visible = is_rgb; rgb_shift_amount_spinbox.visible = is_rgb
	hsv_hue_label.visible = is_hsv; hsv_hue_spinbox.visible = is_hsv
	hsv_sat_label.visible = is_hsv; hsv_sat_spinbox.visible = is_hsv
	hsv_val_label.visible = is_hsv; hsv_val_spinbox.visible = is_hsv

# --- Вспомогательная функция перерисовки палитр ---
func _redraw_palettes_with_text() -> void:
	var base_colors_for_display : Array[Color] = []
	for color_int in current_base_colors_int:
		var r = float((color_int >> 16) & 0xFF) / 255.0; var g = float((color_int >> 8) & 0xFF) / 255.0; var b = float(color_int & 0xFF) / 255.0
		base_colors_for_display.append(Color(r, g, b))
	_display_palette(base_colors_for_display, palette_display)
	_display_palette(last_mutated_colors, mutated_palette_display)

# --- Парсер Hex строки (ИСПРАВЛЕННЫЙ) ---
func _parse_input_colors() -> bool:
	current_base_colors_int.clear(); status_label.text = ""
	var input_text = color_input.text.strip_edges()
	if input_text.is_empty():
		status_label.text = "Input is empty."; return true # Пустой ввод - не ошибка

	var parts = input_text.split(",", false)
	var success = false # Флаг, что хотя бы один цвет найден
	var temp_colors_int : Array[int] = [] # Временный массив для валидных цветов

	for part in parts:
		var clean_part = part.strip_edges()
		if clean_part.is_empty(): continue

		var current_color_int: int = -1 # Переменная для текущего цвета

		# --- Логика парсинга одной части ---
		if clean_part.begins_with("0x"):
			var hex_str = clean_part.substr(2)
			if hex_str.is_valid_hex_number(false) and hex_str.length() == 6:
				current_color_int = hex_str.hex_to_int()
			else:
				status_label.text = "Error: Invalid hex value '%s'." % clean_part
				return false # Ошибка -> выходим, не сохраняя ничего
		elif clean_part.length() == 6 and clean_part.is_valid_hex_number(false):
			current_color_int = clean_part.hex_to_int()
		else:
			status_label.text = "Error: Invalid hex format '%s'." % clean_part
			return false # Ошибка -> выходим, не сохраняя ничего

		# --- Проверка диапазона (current_color_int теперь точно определен или был -1) ---
		if current_color_int < 0 or current_color_int > 0xFFFFFF:
			# Эта проверка сработает, если парсинг выше как-то дал невалидный int,
			# хотя hex_to_int обычно не должен давать < 0. Но оставим для надежности.
			status_label.text = "Error: Parsed color value out of range for '%s'." % clean_part
			return false # Ошибка -> выходим

		# --- Добавляем в ВРЕМЕННЫЙ массив ---
		temp_colors_int.append(current_color_int)
		success = true # Хотя бы один цвет успешно спарсен

	# --- Если весь цикл прошел без ошибок ---
	if not success and not input_text.is_empty(): # Если были символы, но ни один не распознан
		status_label.text = "No valid colors found in input."
		return false # Считаем это ошибкой

	# --- Копируем результат во внутренний массив ---
	current_base_colors_int = temp_colors_int
	return true # Все прошло успешно (или ввод был пуст)

# --- Отображение палитры (визуально, с текстом) ---
func _display_palette(colors: Array[Color], display_container: HBoxContainer) -> void:
	for child in display_container.get_children(): child.queue_free(); if colors.is_empty(): return
	for color_val in colors:
		var rect = ColorRect.new(); rect.color = color_val; rect.custom_minimum_size = Vector2(50, 50)
		rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rect.size_flags_vertical = Control.SIZE_EXPAND_FILL; rect.size_flags_stretch_ratio = 1.0
		display_container.add_child(rect)
		if show_palette_text:
			var label = Label.new(); label.text = _get_formatted_palette_text(color_val, palette_text_format)
			label.add_theme_font_size_override("font_size", palette_text_size); label.add_theme_color_override("font_color", palette_text_color)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_preset(Control.PRESET_FULL_RECT); label.offset_left = 0.0; label.offset_top = 0.0; label.offset_right = 0.0; label.offset_bottom = 0.0
			rect.add_child(label)

# --- Helper для форматирования текста на плашке ---
func _get_formatted_palette_text(color: Color, format_string: String) -> String:
	var result = format_string; result = result.replace("%hex%", color.to_html(false)); result = result.replace("%0xhex%", "0x" + color.to_html(false))
	# Добавил вывод Saturation для отладки
	result = result.replace("%rgb%", "%.3f, %.3f, %.3f (S:%.3f)" % [color.r, color.g, color.b, color.s])
	result = result.replace("%r%", str(color.r8)); result = result.replace("%g%", str(color.g8)); result = result.replace("%b%", str(color.b8))
	# Добавлен вывод S для отладки
	result = result.replace("%s%", "%.3f" % color.s)
	return result

# --- Отображение цветов в GridContainer (текст, ИСПРАВЛЕНИЕ ОШИБКИ) ---
func _display_output_color_fields(colors: Array[Color], output_grid: GridContainer) -> void:
	# Очищаем предыдущие элементы
	for child in output_grid.get_children():
		child.queue_free()

	if colors.is_empty():
		# Если цветов нет, просто выходим. Не устанавливаем columns.
		return

	# Устанавливаем количество колонок ТОЛЬКО если есть цвета
	# Здесь colors.size() гарантированно >= 1
	output_grid.columns = colors.size()

	# Создаем строки для вывода
	var rows: Array[Array] = [[], [], []] # 0=0xHex, 1=Hex, 2="R, G, B" (float)
	for color_val in colors:
		var hex_str_no_prefix = color_val.to_html(false)
		var hex_str_prefix = "0x" + hex_str_no_prefix
		var rgb_str = "%.3f, %.3f, %.3f" % [color_val.r, color_val.g, color_val.b]
		var texts = [hex_str_prefix, hex_str_no_prefix, rgb_str]
		for i in range(texts.size()):
			var le = LineEdit.new()
			le.text = texts[i]
			le.editable = false
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows[i].append(le)

	# Добавляем в грид
	for row_array in rows:
		for le in row_array:
			output_grid.add_child(le)

# --- Вспомогательная функция очистки результатов ---
func _clear_mutation_results(): last_mutated_colors.clear(); _display_palette([], mutated_palette_display); _display_output_color_fields([], mutated_colors_text_grid)

# --- Обработчик нажатия кнопки Mutate ---
func _on_mutate_button_pressed() -> void:
	if not _parse_and_display_input(): return
	if current_base_colors_int.is_empty():
		if status_label.text == "Input is empty.": status_label.text = "Input is empty. Enter colors to mutate."
		_clear_mutation_results(); _display_palette([], palette_display); return

	var mutated_colors: Array[Color] = []; var warnings = ""; var max_attempts = _MAX_MUTATION_ATTEMPTS
	status_label.text = "Mutating colors using %s method..." % ShiftMethod.keys()[current_shift_method]
	await get_tree().process_frame

	for base_int in current_base_colors_int:
		var best_attempt_color : Color; var min_brightness_found = INF; var found_suitable = false
		for attempt in range(max_attempts):
			var current_attempt_color: Color
			match current_shift_method:
				ShiftMethod.RGB: current_attempt_color = _apply_rgb_shift(base_int)
				ShiftMethod.HSV:
					var r_base = float((base_int >> 16) & 0xFF) / 255.0; var g_base = float((base_int >> 8) & 0xFF) / 255.0; var b_base = float(base_int & 0xFF) / 255.0
					current_attempt_color = _apply_hsv_shift(Color(r_base, g_base, b_base))
			var current_brightness = get_brightness(current_attempt_color)
			if attempt == 0 or current_brightness < min_brightness_found: min_brightness_found = current_brightness; best_attempt_color = current_attempt_color
			if current_brightness <= current_brightness_limit: found_suitable = true; best_attempt_color = current_attempt_color; break
		if not found_suitable:
			mutated_colors.append(best_attempt_color); var r_base = float((base_int >> 16) & 0xFF) / 255.0; var g_base = float((base_int >> 8) & 0xFF) / 255.0; var b_base = float(base_int & 0xFF) / 255.0
			warnings += "Warn: No mutation below limit for %s after %d attempts (using darkest found: %.1f). " % [Color(r_base, g_base, b_base).to_html(false), max_attempts, min_brightness_found]
		else: mutated_colors.append(best_attempt_color)

	last_mutated_colors = mutated_colors; _display_palette(mutated_colors, mutated_palette_display); _display_output_color_fields(mutated_colors, mutated_colors_text_grid)
	status_label.text = "Mutated palette generated (%s Shift, Max Brightness: %.1f). %s" % [ShiftMethod.keys()[current_shift_method], current_brightness_limit, warnings.strip_edges()]

# --- Функция парсинга И ОТОБРАЖЕНИЯ ОРИГИНАЛА ---
func _parse_and_display_input() -> bool:
	if not _parse_input_colors(): _display_palette([], palette_display); _clear_mutation_results(); return false
	var base_colors_for_display: Array[Color] = []
	for color_int in current_base_colors_int:
		var r=float((color_int>>16)&0xFF)/255.0; var g=float((color_int>>8)&0xFF)/255.0; var b=float(color_int&0xFF)/255.0
		base_colors_for_display.append(Color(r, g, b, 1.0))
	_display_palette(base_colors_for_display, palette_display)
	_clear_mutation_results()
	if current_base_colors_int.is_empty() and color_input.text.strip_edges().is_empty(): pass
	elif not status_label.text.begins_with("Error"): status_label.text = "Input parsed. Press 'Mutate'."
	return true
