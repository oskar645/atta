/// ========================================
/// SUPABASE CONFIGURATION FOR ATTA
/// ========================================
///
/// Этот файл содержит конфигурацию для подключения к Supabase.
/// Скопируй данные в lib/src/supabase_env.dart
///
/// ========================================
/// ИНСТРУКЦИЯ:
/// ========================================
///
/// 1. Зайди на https://supabase.com
/// 2. Создай новый проект или выбери существующий
/// 3. Перейди в Settings → API
/// 4. Найди:
///    - Project URL → это твой [URL]
///    - Publishable key (anon, public) → это твой [ANON_KEY]
/// 5. Скопируй значения ниже в lib/src/supabase_env.dart
///
/// ========================================
/// СТРУКТУРА ТАБЛИЦ SUPABASE (SQL):
/// ========================================

/*

-- 1. USERS TABLE (профили пользователей)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  email TEXT UNIQUE,
  phone TEXT,
  photo_url TEXT,
  bio TEXT,
  location TEXT,
  rating DECIMAL(3,2) DEFAULT 5.0,
  total_reviews INT DEFAULT 0,
  is_admin BOOLEAN DEFAULT FALSE,
  is_seller BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 2. LISTINGS TABLE (объявления)
CREATE TABLE public.listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL, -- 'cars', 'electronics', etc
  price DECIMAL(12,2) NOT NULL,
  location TEXT,
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  status TEXT DEFAULT 'active', -- 'active', 'sold', 'archived'
  views INT DEFAULT 0,
  images TEXT[], -- массив URL фото
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 3. FAVORITES TABLE (избранные объявления)
CREATE TABLE public.favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, listing_id)
);

-- 4. MESSAGES TABLE (личные сообщения)
CREATE TABLE public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  text TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 5. CHATS TABLE (чаты/диалоги)
CREATE TABLE public.chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user1_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user2_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  last_message TEXT,
  last_message_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user1_id, user2_id)
);

-- 6. REVIEWS TABLE (отзывы)
CREATE TABLE public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reviewer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  rating INT CHECK (rating >= 1 AND rating <= 5),
  text TEXT,
  reviewer_name TEXT,
  reply_text TEXT,
  reply_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP
);

-- 7. REPORTS TABLE (жалобы/отчеты)
CREATE TABLE public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  reason TEXT NOT NULL, -- 'spam', 'fake', 'offensive', etc
  description TEXT,
  status TEXT DEFAULT 'pending', -- 'pending', 'reviewed', 'resolved'
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 8. SUPPORT TICKETS TABLE (тикеты поддержки)
CREATE TABLE public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  description TEXT,
  category TEXT, -- 'bug', 'feature_request', 'other'
  status TEXT DEFAULT 'open', -- 'open', 'in_progress', 'closed'
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 9. CAR SPECS TABLE (характеристики автомобилей)
CREATE TABLE public.car_specs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
  make TEXT, -- Марка: Toyota, BMW, etc
  model TEXT, -- Модель: Camry, X5, etc
  year INT,
  mileage INT, -- в км
  condition TEXT, -- 'new', 'excellent', 'good', 'fair'
  transmission TEXT, -- 'automatic', 'manual'
  fuel_type TEXT, -- 'petrol', 'diesel', 'electric', 'hybrid'
  engine_cc INT, -- объем двигателя в cc
  color TEXT,
  vin TEXT, -- VIN номер
  created_at TIMESTAMP DEFAULT NOW()
);

*/

/// ========================================
/// СКОПИРУЙ В: lib/src/supabase_env.dart
/// ========================================

class SupabaseEnv {
  /// Project URL (Settings → API → Project URL)
  /// Пример: https://your-project.supabase.co
  static const String url = 'ТВ_URL_ЗДЕСЬ';

  /// Public anon key (Settings → API → Publishable key)
  /// Пример: sb_anonkey_xxxxxxxxxxxxx
  static const String anonKey = 'ТВ_ANON_KEY_ЗДЕСЬ';
}

/// ========================================
/// ПОСЛЕ ЗАПОЛНЕНИЯ:
/// ========================================
///
/// 1. Заполни URL и anonKey выше
/// 2. Скопируй весь код из класса SupabaseEnv
/// 3. Вставь в lib/src/supabase_env.dart
/// 4. В терминале выполни: flutter pub get
/// 5. Запусти: flutter run
///
/// ✅ Все должно заработать!
///
