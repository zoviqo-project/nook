package com.nook.config;

import com.nook.domain.SocialEntities.*;
import com.nook.repository.SocialRepository;
import jakarta.transaction.Transactional;
import java.time.*;
import java.util.*;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

@Component
@org.springframework.context.annotation.Profile("demo")
public class DemoDataInitializer implements CommandLineRunner {
  private final SocialRepository repo;
  private final PasswordEncoder encoder;

  public DemoDataInitializer(SocialRepository repo, PasswordEncoder encoder) {
    this.repo = repo;
    this.encoder = encoder;
  }

  @Override
  @Transactional
  public void run(String... args) {
    if (repo.userByEmail("albert@nook.demo").isPresent()) {
      if (!repo.shopProviderExists("barcelona-demo-0")) {
        repo.deactivateSeedShops();
        seedBarcelonaCoffeeShops();
      }
      return;
    }
    var users = seedUsers();
    var shops = seedBarcelonaCoffeeShops();
    seedSocialStory(users, shops);
  }

  private List<User> seedUsers() {
    String[] names = {"Albert", "Laura", "Marta", "Sofía", "Clara", "Emma", "Lucía", "Elena", "Paula", "Carla", "Alex", "Dani", "Hugo", "Marc", "Leo", "Nora", "Irene", "Julia", "Aina", "Valentina"};
    String[] coffees = {"Solo ☕", "Café con leche 🥛", "Matcha 🍵", "Café frío 🧊", "Cortado ☕🥛"};
    String[] photos = {
      "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=1000&q=85",
      "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1000&q=85",
      "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=1000&q=85",
      "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1000&q=85"
    };
    List<User> users = new ArrayList<>();
    for (int i = 0; i < names.length; i++) {
      User user = new User();
      user.email = (i == 0 ? "albert" : names[i].toLowerCase()) + "@nook.demo";
      user.passwordHash = encoder.encode("Coffee123!");
      repo.save(user);

      Profile profile = new Profile();
      profile.user = user;
      profile.name = names[i];
      profile.birthDate = LocalDate.of(1990 + i % 12, 1 + i % 11, 2 + i % 20);
      profile.gender = i % 3 == 0 ? Gender.MAN : Gender.WOMAN;
      profile.bio = new String[] {"Arquitectura · conciertos · cafeterías pequeñas", "Libros · cerámica · conversaciones largas", "Fotografía · viajes · café por la mañana", "Producto · música · paseos sin prisa"}[i % 4];
      profile.city = "Barcelona";
      profile.latitude = 41.3874 + (i % 5) * .003;
      profile.longitude = 2.1686 + (i % 4) * .003;
      profile.lookingFor = LookingFor.values()[i % 4];
      profile.coffeePersonality = coffees[i % coffees.length];
      profile.preferredPlan = new String[] {"QUICK", "LONG_TALKS", "WALK", "IMPROVISE"}[i % 4];
      profile.preferredVibe = new String[] {"CALM", "SOCIAL", "LIVELY"}[i % 3];
      profile.coffeesPerDay = i % 5;
      profile.favoriteCoffeeMoment = new String[] {"MORNING", "MIDDAY", "AFTERWORK", "EVENING"}[i % 4];
      profile.onboardingComplete = true;
      repo.save(profile);

      Preference preference = new Preference();
      preference.user = user;
      preference.minAge = 18;
      preference.maxAge = 55;
      preference.maxDistanceKm = 40;
      repo.save(preference);

      CoffeePreference coffee = new CoffeePreference();
      coffee.userId = user.id;
      coffee.preference = new String[] {"BLACK", "CORTADO", "MILK_COFFEE", "ICED_COFFEE", "MATCHA", "TEA"}[i % 6];
      repo.save(coffee);

      Photo photo = new Photo();
      photo.userId = user.id;
      photo.url = photos[i % photos.length];
      photo.position = 0;
      repo.save(photo);
      users.add(user);
    }
    return users;
  }

  private List<CoffeeShop> seedBarcelonaCoffeeShops() {
    String[][] values = {
      {"Nomad Coffee", "El Born", "CALM", "Perfecto para hablar"},
      {"Satan's Coffee Corner", "Barri Gòtic", "LIVELY", "Más energía y movimiento"},
      {"Three Marks Coffee", "Fort Pienc", "SOCIAL", "Movimiento, pero se puede conversar"},
      {"Hidden Coffee Roasters", "Les Corts", "CALM", "Perfecto para hablar"},
      {"Syra Coffee", "Poble-sec", "SOCIAL", "Movimiento, pero se puede conversar"},
      {"Dalston Coffee", "El Raval", "LIVELY", "Más energía y movimiento"},
      {"SlowMov", "Gràcia", "CALM", "Perfecto para hablar"},
      {"Onna Coffee", "Gràcia", "CALM", "Perfecto para hablar"},
      {"Departure Coffee", "Esquerra de l'Eixample", "SOCIAL", "Movimiento, pero se puede conversar"},
      {"News & Coffee", "Sant Antoni", "LIVELY", "Más energía y movimiento"},
      {"Federal Café", "Sant Antoni", "SOCIAL", "Movimiento, pero se puede conversar"},
      {"Café Cometa", "Sant Antoni", "CALM", "Perfecto para hablar"},
      {"Roast Club", "Eixample", "SOCIAL", "Movimiento, pero se puede conversar"},
      {"Morrow Coffee", "Sant Antoni", "CALM", "Perfecto para hablar"},
      {"The Miners", "Poblenou", "LIVELY", "Más energía y movimiento"}
    };
    String[] images = {
      "https://images.unsplash.com/photo-1445116572660-236099ec97a0?auto=format&fit=crop&w=1400&q=85",
      "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1400&q=85",
      "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?auto=format&fit=crop&w=1400&q=85",
      "https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=1400&q=85",
      "https://images.unsplash.com/photo-1559925393-8be0ec4767c8?auto=format&fit=crop&w=1400&q=85"
    };
    List<CoffeeShop> shops = new ArrayList<>();
    for (int i = 0; i < values.length; i++) {
      CoffeeShop shop = new CoffeeShop();
      shop.providerId = "barcelona-demo-" + i;
      shop.name = values[i][0];
      shop.neighborhood = values[i][1];
      shop.address = values[i][1] + ", Barcelona";
      shop.latitude = 41.386 + (i % 5) * .004;
      shop.longitude = 2.165 + (i % 3) * .005;
      shop.photoUrl = images[i % images.length];
      shop.openingHours = null;
      shop.rating = null;
      shop.description = values[i][3];
      repo.save(shop);

      CoffeeShopVibe vibe = new CoffeeShopVibe();
      vibe.coffeeShopId = shop.id;
      vibe.vibe = values[i][2];
      repo.save(vibe);
      shops.add(shop);
    }
    return shops;
  }

  private void seedSocialStory(List<User> users, List<CoffeeShop> shops) {
    for (int i = 2; i < 10; i++) {
      CoffeeLike like = new CoffeeLike();
      like.senderId = users.get(i).id;
      like.receiverId = users.get(0).id;
      repo.save(like);
    }
    CoffeeLike fromAlbert = new CoffeeLike();
    fromAlbert.senderId = users.get(0).id;
    fromAlbert.receiverId = users.get(1).id;
    repo.save(fromAlbert);
    CoffeeLike fromLaura = new CoffeeLike();
    fromLaura.senderId = users.get(1).id;
    fromLaura.receiverId = users.get(0).id;
    repo.save(fromLaura);

    Match match = new Match();
    match.userOneId = users.get(0).id.toString().compareTo(users.get(1).id.toString()) < 0 ? users.get(0).id : users.get(1).id;
    match.userTwoId = match.userOneId.equals(users.get(0).id) ? users.get(1).id : users.get(0).id;
    repo.save(match);
    Conversation conversation = new Conversation();
    conversation.matchId = match.id;
    repo.save(conversation);
    Message message = new Message();
    message.conversationId = conversation.id;
    message.senderId = users.get(1).id;
    message.body = "¿Te apetece un café esta semana? ☕";
    repo.save(message);
    CoffeeDateProposal proposal = new CoffeeDateProposal();
    proposal.senderId = users.get(1).id;
    proposal.receiverId = users.get(0).id;
    proposal.matchId = match.id;
    proposal.coffeeShopId = shops.get(0).id;
    proposal.proposedAt = Instant.now().plus(3, java.time.temporal.ChronoUnit.DAYS);
    proposal.paymentPreference = PaymentPreference.I_INVITE;
    repo.save(proposal);
  }
}
