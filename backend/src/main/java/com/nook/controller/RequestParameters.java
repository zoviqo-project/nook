package com.nook.controller;

import com.nook.exception.ApiException;
import org.springframework.http.HttpStatus;

final class RequestParameters {
  private RequestParameters() {}

  static int page(int value) {
    if (value < 0) throw invalid("La página no puede ser negativa");
    return value;
  }

  static int size(int value, int maximum) {
    if (value < 1) throw invalid("El tamaño debe ser mayor que cero");
    return Math.min(value, maximum);
  }

  private static ApiException invalid(String message) {
    return new ApiException(HttpStatus.BAD_REQUEST, "INVALID_PAGINATION", message);
  }
}
