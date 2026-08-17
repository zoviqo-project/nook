package com.nook.exception;

import com.nook.dto.ApiDtos.ErrorDto;
import jakarta.servlet.http.HttpServletRequest;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
  private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

  @ExceptionHandler(ApiException.class)
  ResponseEntity<ErrorDto> api(ApiException exception, HttpServletRequest request) {
    return response(exception.status, exception.code, exception.getMessage(), request, Map.of());
  }

  @ExceptionHandler(BadCredentialsException.class)
  ResponseEntity<ErrorDto> auth(BadCredentialsException exception, HttpServletRequest request) {
    return response(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "Credenciales no válidas", request, Map.of());
  }

  @ExceptionHandler(MethodArgumentNotValidException.class)
  ResponseEntity<ErrorDto> validation(MethodArgumentNotValidException exception, HttpServletRequest request) {
    Map<String, String> fields = new LinkedHashMap<>();
    exception.getBindingResult().getFieldErrors()
        .forEach(error -> fields.put(error.getField(), error.getDefaultMessage()));
    return response(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "Revisa los campos", request, fields);
  }

  @ExceptionHandler(DataIntegrityViolationException.class)
  ResponseEntity<ErrorDto> conflict(DataIntegrityViolationException exception, HttpServletRequest request) {
    log.info("Database constraint rejected method={} path={}", request.getMethod(), request.getRequestURI());
    return response(HttpStatus.CONFLICT, "DATA_CONFLICT",
        "La operación ya se había realizado o entra en conflicto con el estado actual", request, Map.of());
  }

  @ExceptionHandler(Exception.class)
  ResponseEntity<ErrorDto> other(Exception exception, HttpServletRequest request) {
    if (isClientDisconnect(exception)) {
      log.debug("Client disconnected method={} path={}", request.getMethod(), request.getRequestURI());
      return null;
    }
    log.error("Unhandled API error method={} path={}", request.getMethod(), request.getRequestURI(), exception);
    return response(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_ERROR",
        "No hemos podido completar la operación", request, Map.of());
  }

  private ResponseEntity<ErrorDto> response(
      HttpStatus status, String code, String message, HttpServletRequest request,
      Map<String, String> fields) {
    ErrorDto body = new ErrorDto(
        Instant.now(), status.value(), code, message, request.getRequestURI(), fields);
    // Explicit JSON prevents an image endpoint's preset content type from being reused by
    // the exception resolver when the upstream photo request fails.
    return ResponseEntity.status(status).contentType(MediaType.APPLICATION_JSON).body(body);
  }

  private boolean isClientDisconnect(Throwable exception) {
    for (Throwable current = exception; current != null; current = current.getCause()) {
      String name = current.getClass().getName();
      if (name.equals("org.apache.catalina.connector.ClientAbortException")
          || name.equals("org.springframework.web.context.request.async.AsyncRequestNotUsableException")) {
        return true;
      }
      String message = current.getMessage();
      if (message != null && (message.contains("Broken pipe") || message.contains("Connection reset"))) {
        return true;
      }
    }
    return false;
  }
}
