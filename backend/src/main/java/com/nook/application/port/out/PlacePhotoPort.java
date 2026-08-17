package com.nook.application.port.out;

public interface PlacePhotoPort {
  PhotoAsset photo(String token);

  record PhotoAsset(byte[] bytes, String contentType) {}
}
