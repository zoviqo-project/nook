package com.nook.dto;
import com.nook.domain.SocialEntities.*; import jakarta.validation.constraints.*; import java.time.*; import java.util.*;
public final class ApiDtos { private ApiDtos(){}
 public record Register(@Email @NotBlank String email,@Size(min=8,max=100) String password,@NotBlank @Size(max=80) String name,@NotNull @Past LocalDate birthDate,@NotNull Gender gender,@NotNull LookingFor lookingFor){}
 public record Login(@Email String email,@NotBlank String password){} public record Refresh(@NotBlank String refreshToken){}
 public record FederatedAuth(@NotBlank String identityToken,String displayName){}
 public record PhoneOtpRequest(@NotBlank @Pattern(regexp="^\\+[1-9][0-9]{7,14}$") String phone){}
 public record PhoneOtpRequested(UUID challengeId,long expiresIn,String developmentCode){}
 public record PhoneOtpVerify(@NotNull UUID challengeId,@NotBlank @Pattern(regexp="^[0-9]{6}$") String code){}
 public record Token(String accessToken,String refreshToken,String tokenType,long expiresIn,Me user){}
 public record Me(UUID id,String email,String name,int age,LocalDate birthDate,Gender gender,String bio,String city,LookingFor lookingFor,String coffeePersonality,String preferredPlan,String preferredVibe,Integer coffeesPerDay,String favoriteCoffeeMoment,int minAge,int maxAge,int maxDistanceKm,boolean visible,boolean hidden,boolean onboardingComplete,List<String> coffeePreferences,List<PhotoDto> photos,List<String> desiredGenders,List<String> discoveryIntentions,List<String> discoveryVibes,List<String> discoveryMoments,List<String> discoveryMeetingStyles){}
 public record UpdateMe(String name,LocalDate birthDate,Gender gender,@Size(max=500) String bio,String city,Double latitude,Double longitude,LookingFor lookingFor,String coffeePersonality,String preferredPlan,String preferredVibe,@Min(0) @Max(4) Integer coffeesPerDay,String favoriteCoffeeMoment,@Min(18) Integer minAge,@Max(100) Integer maxAge,@Min(1) @Max(200) Integer maxDistanceKm,Boolean visible,Boolean hidden,List<String> coffeePreferences,Boolean onboardingComplete,List<String> desiredGenders,List<String> discoveryIntentions,List<String> discoveryVibes,List<String> discoveryMoments,List<String> discoveryMeetingStyles){}
 public record PhotoDto(UUID id,String url,int position,boolean isPrimary){} public record PhotoRequest(@NotBlank String url,Integer position){} public record PhotoOrder(@NotEmpty @Size(max=8) List<UUID> photoIds){}
 public record DiscoverProfile(UUID id,String name,int age,String bio,String city,double distanceKm,String coffeePersonality,String preferredPlan,String preferredVibe,Integer coffeesPerDay,String favoriteCoffeeMoment,LookingFor lookingFor,List<String> coffeePreferences,List<PhotoDto> photos){}
 public record LikeResult(boolean matched,MatchDto match){}
 public record GeoPointDto(double latitude,double longitude){}
 public record MatchDto(UUID id,DiscoverProfile person,Instant matchedAt,UUID conversationId){}
 public record ShopDto(UUID id,String name,String address,String neighborhood,double distanceKm,String photoUrl,String openingHours,Double rating,String description,List<String> vibes,Double latitude,Double longitude,String placeId,Integer reviewCount,Boolean openNow,String priceLevel,String website,String phone,String mapsUrl,List<String> types,List<String> photoUrls,String category){}
 public record CreateDate(@NotNull UUID matchId,@NotNull UUID coffeeShopId,@NotNull Instant proposedAt,@NotNull PaymentPreference paymentPreference,boolean nookChoice,@NotNull UUID idempotencyKey){}
 public record UpdateDate(DateStatus status,Instant proposedAt,UUID coffeeShopId,PaymentPreference paymentPreference){}
 public record DateDto(UUID id,UUID matchId,UUID senderId,UUID receiverId,ShopDto coffeeShop,Instant proposedAt,PaymentPreference paymentPreference,DateStatus status,Instant createdAt,boolean nookChoice){}
 public record ConversationDto(UUID id,UUID matchId,DiscoverProfile person,String lastMessage,Instant updatedAt){}
 public record SendMessage(@NotBlank @Size(max=2000) String body,@NotNull UUID clientMessageId){} public record MessageDto(UUID id,UUID senderId,String body,String type,Instant createdAt){}
 public record ReportRequest(@NotBlank String reason,@Size(max=1000) String details){} public record NotificationDto(UUID id,String type,String title,String body,UUID resourceId,Instant createdAt,boolean read){}
 public record DeviceTokenRequest(@NotBlank @Size(max=300) String token){}
 public record UserSettingsDto(boolean coffeeSoundsEnabled,boolean pushEnabled,String locale){}
 public record UpdateUserSettings(Boolean coffeeSoundsEnabled,Boolean pushEnabled,@Size(max=12) String locale){}
 public record UpdateUserLocation(@DecimalMin("-90.0") @DecimalMax("90.0") double latitude,@DecimalMin("-180.0") @DecimalMax("180.0") double longitude,@DecimalMin("0.0") @DecimalMax("1000.0") double accuracyMeters,@NotNull Instant capturedAt){}
 public record PageDto<T>(List<T> content,int page,int size,boolean hasMore){}
 public record ErrorDto(Instant timestamp,int status,String code,String message,String path,Map<String,String> fields){}
}
