"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.matchesSavedSearchFilters = matchesSavedSearchFilters;
const norm = (value) => `${value ?? ''}`.toLowerCase().replace(/\s+/g, ' ').trim();
const number = (value) => {
    if (value == null || `${value}`.trim() === '')
        return null;
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
};
// Text search is applied using the existing buildListingSearchWhere in the DB.
// These are the persisted feed filters, including the existing 26-part queryKey.
function matchesSavedSearchFilters(listing, search) {
    for (const key of ['category', 'subcategory']) {
        const q = norm(search[key]);
        if (q && q !== 'все' && norm(listing[key]) !== q)
            return false;
    }
    // The current feed treats location without radius as ranking only. There are
    // no saved center coordinates: radius currently enables textual locality.
    if (search.radiusKm != null && norm(search.location)) {
        const location = listing.locationJson;
        const q = norm(search.location);
        const candidates = [listing.city, ...['region', 'district', 'locality', 'subLocality', 'raw'].map(k => location?.[k])];
        if (!candidates.some(value => {
            const text = norm(value);
            return text && (text.includes(q) || q.includes(text));
        }))
            return false;
    }
    const parts = search.queryKey.split('|');
    const extended = parts.length === 26;
    const p = (index) => extended ? parts[index] : '';
    const inRange = (value, min, max) => {
        const lo = number(min), hi = number(max), n = number(value);
        return (lo == null || (n != null && n >= lo)) && (hi == null || (n != null && n <= hi));
    };
    if (!inRange(listing.price, p(3), p(4)))
        return false;
    const car = listing.car;
    const fields = [
        ['brand', search.autoBrand], ['model', search.autoModel], ['condition', search.autoCondition],
        ['transmission', p(15)], ['drive', p(16)], ['bodyType', p(17)], ['fuel', p(18)], ['color', p(19)],
    ];
    for (const [key, query] of fields) {
        if (norm(query) && !norm(car?.[key]).includes(norm(query)))
            return false;
    }
    if (!inRange(car?.year, p(11), p(12)) ||
        !inRange(car?.mileageKm, p(13), search.autoMileageTo) ||
        !inRange(car?.engineVolume, p(20), p(21)))
        return false;
    if (number(p(22)) != null && number(car?.owners) !== number(p(22)))
        return false;
    if (p(23) && car?.isCleared !== (p(23) === 'true'))
        return false;
    if (search.onlyUncrashed) {
        // Same conservative text heuristic as the existing feed; do not invent a
        // structured accident-history field that the project does not store.
        const source = norm(`${car?.condition ?? ''} ${listing.title} ${listing.description}`);
        const positive = ['не бит', 'без дтп', 'не крашен', 'родной окрас'].some(x => source.includes(x));
        const negative = ['бит', 'дтп', 'крашен', 'после авар'].some(x => source.includes(x));
        if (!car || !positive || negative)
            return false;
    }
    return true;
}
//# sourceMappingURL=saved-search-matching.js.map