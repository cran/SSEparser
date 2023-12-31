#' Parse a Server Sent Event
#' 
#' @description
#' This class can help you parse a single server sent event or a stream of them. 
#' You can inherit the class for a custom application. 
#' The [parse_sse()] function wraps this class for a more *functional* approach.
#' 
#' @details
#' The [HTML specification](https://html.spec.whatwg.org/multipage/server-sent-events.html#server-sent-events) 
#' tells us that event streams are composed by chunks (also called *blocks*, or *messages*) and lines. 
#' A single new line character (`\n`) states the end of a line, and two consecutive new line characters (`\n\n`) state the end of a chunk.
#' 
#' This means that, in practice, an event can be composed of one or more chunks, and a chunk can be composed of one or more lines.
#' 
#' ```
#' data: This is the first chunk, it has one line
#' 
#' data: This is the second chunk
#' extra: It has two lines
#' 
#' data: This is the third chunk, it has an id field. This is common.
#' id: 123
#' 
#' : Lines that start with a colon are comments, they will be ignored
#' data: This is the forth chunk, it has a comment
#' 
#' data: This is the fifth chunk. Normally you will receive a data field
#' custom: But the server can send custom field names. SSEparser parses them too.
#' 
#' ```
#' 
#' Typically, an event stream will send a single chunk for event, but it is important 
#' to understand that event != chunk because `SSEparser$events` will be a list of
#' all the chunks received as it makes a more consistent output. 
#' 
#' 
#' @param event A length 1 string containing a server sent event as specified in the [HTML spec](https://html.spec.whatwg.org/multipage/server-sent-events.html#server-sent-events).
#' @param parsed_event Event to append to the `events` field.
#' 
#' @importFrom R6 R6Class
#' @importFrom rlang is_empty
#' @importFrom stringr str_split str_starts str_detect str_split_1 str_trim
#' @importFrom purrr pluck map discard reduce compact
#' 
#' @returns An object with R6 class `SSEparser`
#' 
#' @export
#' 
#' @examples
#' example_event <- 
#' "data: This is the first chunk, it has one line
#' 
#' data: This is the second chunk
#' extra: It has two lines
#' 
#' data: This is the third chunk, it has an id field. This is common.
#' id: 123
#' 
#' : Lines that start with a colon are comments, they will be ignored
#' data: This is the fourth chunk, it has a comment
#'
#' data: This is the fifth chunk. Normally you will receive a data field
#' custom: But the server can send custom field names. SSEparser parses them too."
#'  
#' parser <- SSEparser$new()
#' parser$parse_sse(example_event)
#'  
#' str(parser$events)
#' 
SSEparser <- R6::R6Class(
	classname = "SSEparser",
	portable = TRUE,
	public = list(
		
		#' @field events List  that contains all the events parsed. When the class is initialized, is just an empty list.
		events = NULL,
		
		#' @description Takes a parsed event and appends it to the `events` field. You can overwrite this method if you decide to extend this class.
		append_parsed_sse = function(parsed_event) {
			self$events <- c(self$events, list(parsed_event))
			
			invisible(self)
		},
		
		#' @description Takes a string that comes from a server sent event and parses it to an R list. You should never overwrite this method.
		parse_sse = function(event) {
			chunks <- event %>% 
				stringr::str_split("\n\n") %>%
				purrr::pluck(1L)
			
			parsed_chunks <-  chunks %>% 
				purrr::map(private$parse_chunk) %>% 
				purrr::discard(rlang::is_empty)
			
			parsed_chunks %>%
				purrr::walk(self$append_parsed_sse)
			
			invisible(self)
		},
		
		#' @description Create a new SSE parser
		initialize = function() {
			self$events <- list()
		}
	),
	private = list(
		
		parse_chunk = function(chunk) {
			lines <- chunk %>%
				stringr::str_split("\n") %>%
				purrr::pluck(1L) 
			
			lines %>% 
				purrr::map(private$parse_line) %>% 
				purrr::discard(rlang::is_empty) %>% # ignore comments
				purrr::reduce(c, .init = list())
		},
		
		parse_line = function(line) {
			# https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
			
			# If the line is empty (a blank line)
			# Dispatch the event. In our case, we just return NULL, to ignore it later
			if(line == "") return()
			
			# If the line starts with a U+003A COLON character (:) -> Ignore the line
			if (stringr::str_starts(line, ":")) return()
			
			# If the line contains a U+003A COLON character (:)
			# 1. Collect the characters on the line before the first (:), and let field be that string.
			# 2. Collect the characters on the line after the first (:), and let value be that string. 
			#    If value starts with a U+0020 SPACE character, remove it from value.
			output <- list()
			if (stringr::str_detect(line, ":")) {
				splitted <- stringr::str_split_1(line, ":")
				field <- splitted[1]
				value <- paste0(splitted[2:length(splitted)], collapse = ":") %>% 
					stringr::str_trim("left")
			} else {
				field <- line
				value <- ""
			}
			
			# Otherwise, the string is not empty but does not contain a U+003A COLON character (:)
			# Process the field using the steps described below, using the whole line as the field name, 
			# and the empty string as the field value.
			output[[field]] <- value
			output
		}
	)
)
