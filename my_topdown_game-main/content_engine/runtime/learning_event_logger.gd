class_name LearningEventLogger
extends RefCounted

const EVENT_PATH := "user://data_garden_learning_events_v1.jsonl"
const MAX_UPLOAD_QUEUE := 256

var enabled := true
var session_id := ""
var anonymous_student_id := ""
var content_metadata: Dictionary = {}
var event_schema_version := "1.0.0"
var session_started_msec := 0
var upload_endpoint := ""
var upload_request: HTTPRequest
var upload_queue: Array[Dictionary] = []
var upload_in_flight := false
var failed_uploads := 0


func setup(
	metadata: Dictionary,
	student_id: String,
	enabled_value: bool = true,
	host_node: Node = null,
	upload_endpoint_value: String = ""
) -> void:
	content_metadata = metadata.duplicate(true)
	anonymous_student_id = student_id
	enabled = enabled_value
	event_schema_version = str(metadata.get("event_schema_version", "1.0.0"))
	session_started_msec = Time.get_ticks_msec()
	var random_bytes := Crypto.new().generate_random_bytes(12)
	session_id = "session_%s" % random_bytes.hex_encode()
	upload_endpoint = upload_endpoint_value.strip_edges()
	if enabled and host_node and not upload_endpoint.is_empty():
		upload_request = HTTPRequest.new()
		upload_request.name = "LearningEventUploadRequest"
		upload_request.timeout = 4.0
		host_node.add_child(upload_request)
		upload_request.request_completed.connect(_on_upload_completed)


func log_event(event_name: String, stage_name: String, payload: Dictionary = {}) -> Dictionary:
	var random_bytes := Crypto.new().generate_random_bytes(10)
	var event := {
		"event_schema_version": event_schema_version,
		"event_id": "evt_%s" % random_bytes.hex_encode(),
		"occurred_at": Time.get_datetime_string_from_system(false, false),
		"elapsed_ms": maxi(0, Time.get_ticks_msec() - session_started_msec),
		"anonymous_student_id": anonymous_student_id,
		"session_id": session_id,
		"unit_id": str(content_metadata.get("unit_id", "")),
		"version": str(content_metadata.get("version", "")),
		"content_hash": str(content_metadata.get("content_hash", "")),
		"event_name": event_name,
		"stage": stage_name,
		"payload": payload.duplicate(true),
	}
	if not enabled:
		return event

	var file: FileAccess
	if FileAccess.file_exists(EVENT_PATH):
		file = FileAccess.open(EVENT_PATH, FileAccess.READ_WRITE)
		if file:
			file.seek_end()
	else:
		file = FileAccess.open(EVENT_PATH, FileAccess.WRITE)
	if file:
		file.store_line(JSON.stringify(event))
	_queue_upload(event)
	return event


func _queue_upload(event: Dictionary) -> void:
	if not upload_request or upload_endpoint.is_empty():
		return
	if upload_queue.size() >= MAX_UPLOAD_QUEUE:
		upload_queue.pop_front()
	upload_queue.append(event.duplicate(true))
	_send_next_upload()


func _send_next_upload() -> void:
	if upload_in_flight or upload_queue.is_empty() or not upload_request:
		return
	upload_in_flight = true
	var request_error := upload_request.request(
		upload_endpoint,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(upload_queue.front())
	)
	if request_error != OK:
		failed_uploads += 1
		upload_queue.pop_front()
		upload_in_flight = false


func _on_upload_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray
) -> void:
	if not upload_queue.is_empty():
		upload_queue.pop_front()
	if result != HTTPRequest.RESULT_SUCCESS or response_code not in [200, 202]:
		failed_uploads += 1
	upload_in_flight = false
	_send_next_upload()
