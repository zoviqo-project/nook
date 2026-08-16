package com.nook;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;
@SpringBootApplication @EnableScheduling public class NookApplication { public static void main(String[] args) { SpringApplication.run(NookApplication.class, args); } }
