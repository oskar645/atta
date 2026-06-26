import { BadRequestException } from '@nestjs/common';

export const normalizeRussianPhone = (phone: string): string => {
  const digits = phone.replace(/\D/g, '');
  if (!digits) return '';

  let normalized = digits;
  if (
    normalized.length === 11 &&
    (normalized.startsWith('7') || normalized.startsWith('8'))
  ) {
    normalized = `7${normalized.slice(1)}`;
  }

  if (normalized.length !== 11 || !normalized.startsWith('7')) {
    return '';
  }

  return normalized;
};

export const validateRussianPhoneOrThrow = (phone: string): void => {
  if (!/^7\d{10}$/.test(phone)) {
    throw new BadRequestException('Введите корректный номер телефона');
  }
};

export const maskPhone = (phone: string): string => {
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) {
    return '***';
  }

  return `***${digits.slice(-4)}`;
};
