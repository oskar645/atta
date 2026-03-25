-- ========================================
-- ATTA - SUPABASE SQL SETUP
-- ========================================
-- Копируй каждый блок в SQL Editor Supabase и выполни (Run)
-- ========================================

-- ⚠️ УДАЛИ СТАРЫЕ ТАБЛИЦЫ (выполни первым!)
DROP TABLE IF EXISTS public.support_tickets CASCADE;
DROP TABLE IF EXISTS public.reports CASCADE;
DROP TABLE IF EXISTS public.reviews CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.chats CASCADE;
DROP TABLE IF EXISTS public.favorites CASCADE;
DROP TABLE IF EXISTS public.listings CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;

-- ========================================
-- 1️⃣ ТАБЛИЦА USERS (Профили пользователей)
-- ========================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  display_name TEXT,
  phone TEXT,
  photo_url TEXT,
  bio TEXT,
  city TEXT,
  is_seller BOOLEAN DEFAULT FALSE,
  rating DECIMAL(3,2) DEFAULT 5.0,
  total_reviews INT DEFAULT 0,
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS Policy для users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read all profiles" ON public.users FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.users FOR INSERT WITH CHECK (auth.uid() = id);

-- ========================================
-- 2️⃣ ТАБЛИЦА LISTINGS (Объявления)
-- ========================================
CREATE TABLE IF NOT EXISTS public.listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  owner_email TEXT NOT NULL,
  owner_name TEXT,
  
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL, -- 'cars', 'electronics', 'real_estate', 'clothes', 'other'
  subcategory TEXT,
  
  price INTEGER NOT NULL,
  phone TEXT,
  phone_hidden BOOLEAN DEFAULT FALSE,
  city TEXT NOT NULL,
  latitude DECIMAL(10,8),
  longitude DECIMAL(11,8),
  
  photo_urls TEXT[] DEFAULT '{}', -- массив URL фотографий
  
  -- Доп. информация по категориям
  delivery JSONB DEFAULT '{}',
  car_specs JSONB, -- для авто: марка, модель, год, пробег
  deal_type TEXT, -- 'sale', 'exchange', 'rent'
  real_estate_type TEXT, -- 'apartment', 'house', 'land'
  clothes_type TEXT, -- 'men', 'women', 'children'
  
  view_count INTEGER DEFAULT 0,
  status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected', 'sold', 'archived'
  rejection_reason TEXT,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- RLS для listings
ALTER TABLE public.listings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read approved listings" ON public.listings FOR SELECT USING (status = 'approved' OR auth.uid() = owner_id);
CREATE POLICY "Users can create listings" ON public.listings FOR INSERT WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "Users can update own listings" ON public.listings FOR UPDATE USING (auth.uid() = owner_id);
CREATE POLICY "Users can delete own listings" ON public.listings FOR DELETE USING (auth.uid() = owner_id);

-- ========================================
-- 3️⃣ ТАБЛИЦА FAVORITES (Избранные объявления)
-- ========================================
CREATE TABLE IF NOT EXISTS public.favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, listing_id)
);

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own favorites" ON public.favorites USING (auth.uid() = user_id);

-- ========================================
-- 4️⃣ ТАБЛИЦА CHATS (Чаты/Диалоги)
-- ========================================
CREATE TABLE IF NOT EXISTS public.chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user1_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user2_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  
  last_message TEXT,
  last_message_at TIMESTAMP WITH TIME ZONE,
  member_ids TEXT[] DEFAULT '{}', -- для быстрого фильтра
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(user1_id, user2_id)
);

ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own chats" ON public.chats USING (auth.uid() = user1_id OR auth.uid() = user2_id);
CREATE POLICY "Users can create chats" ON public.chats FOR INSERT WITH CHECK (auth.uid() = user1_id OR auth.uid() = user2_id);

-- ========================================
-- 5️⃣ ТАБЛИЦА MESSAGES (Сообщения в чате)
-- ========================================
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  
  text TEXT NOT NULL,
  photo_url TEXT,
  
  is_read BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read messages from own chats" ON public.messages USING (
  EXISTS (
    SELECT 1 FROM public.chats c 
    WHERE c.id = messages.chat_id 
    AND (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
  )
);
CREATE POLICY "Users can create messages" ON public.messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- ========================================
-- 6️⃣ ТАБЛИЦА REVIEWS (Отзывы/Рейтинги)
-- ========================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reviewer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reviewee_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  text TEXT,
  reviewer_name TEXT,
  
  reply_text TEXT,
  reply_at TIMESTAMP WITH TIME ZONE,
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read reviews" ON public.reviews FOR SELECT USING (true);
CREATE POLICY "Users can create reviews" ON public.reviews FOR INSERT WITH CHECK (auth.uid() = reviewer_id);
CREATE POLICY "Seller can update their reviews" ON public.reviews FOR UPDATE USING (auth.uid() = reviewee_id);

-- ========================================
-- 7️⃣ ТАБЛИЦА REPORTS (Жалобы/Отчеты)
-- ========================================
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  listing_id UUID REFERENCES public.listings(id) ON DELETE SET NULL,
  
  reason TEXT NOT NULL, -- 'spam', 'fake', 'offensive', 'stolen', 'other'
  description TEXT,
  status TEXT DEFAULT 'pending', -- 'pending', 'reviewed', 'resolved'
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can report" ON public.reports FOR INSERT WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY "Only admins can see reports" ON public.reports FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND is_admin = true)
);

-- ========================================
-- 8️⃣ ТАБЛИЦА SUPPORT TICKETS
-- ========================================
CREATE TABLE IF NOT EXISTS public.support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  
  subject TEXT NOT NULL,
  description TEXT,
  category TEXT, -- 'bug', 'feature_request', 'account_issue', 'other'
  status TEXT DEFAULT 'open', -- 'open', 'in_progress', 'closed'
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage own tickets" ON public.support_tickets USING (auth.uid() = user_id);

-- ========================================
-- ГОТОВО! ✅
-- ========================================
-- Теперь у тебя есть вся структура базы данных.
-- 
-- Дальше:
-- 1. Скопируй URL и anonKey из Settings → API
-- 2. Вставь в lib/src/supabase_env.dart
-- 3. Запусти: flutter pub get && flutter run
-- 
-- Приложение должно заработать! 🚀
