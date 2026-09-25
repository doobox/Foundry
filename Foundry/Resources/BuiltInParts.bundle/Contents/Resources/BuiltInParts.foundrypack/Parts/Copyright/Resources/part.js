const year = String(new Date().getFullYear());
const yearElement = part.querySelector("[data-current-year]");

if (yearElement) {
    yearElement.textContent = year;
}
