"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.maskPhone = exports.validateRussianPhoneOrThrow = exports.normalizeRussianPhone = void 0;
const common_1 = require("@nestjs/common");
const normalizeRussianPhone = (phone) => {
    const digits = phone.replace(/\D/g, '');
    if (!digits)
        return '';
    let normalized = digits;
    if (normalized.length === 11 &&
        (normalized.startsWith('7') || normalized.startsWith('8'))) {
        normalized = `7${normalized.slice(1)}`;
    }
    if (normalized.length !== 11 || !normalized.startsWith('7')) {
        return '';
    }
    return normalized;
};
exports.normalizeRussianPhone = normalizeRussianPhone;
const validateRussianPhoneOrThrow = (phone) => {
    if (!/^7\d{10}$/.test(phone)) {
        throw new common_1.BadRequestException('Введите корректный номер телефона');
    }
};
exports.validateRussianPhoneOrThrow = validateRussianPhoneOrThrow;
const maskPhone = (phone) => {
    const digits = phone.replace(/\D/g, '');
    if (digits.length < 4) {
        return '***';
    }
    return `***${digits.slice(-4)}`;
};
exports.maskPhone = maskPhone;
//# sourceMappingURL=phone.js.map