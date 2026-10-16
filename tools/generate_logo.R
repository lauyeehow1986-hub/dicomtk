# tools/generate_logo.R
# Generates the official dicomtk hex sticker in man/figures/logo.png using ggplot2

library(ggplot2)

dir.create("man/figures", recursive = TRUE, showWarnings = FALSE)

# Hexagon vertices
angles <- seq(pi / 6, 2 * pi + pi / 6, length.out = 7)
hex_df <- data.frame(
  x = cos(angles),
  y = sin(angles)
)

# Synthetic radial CT/MRI brain phantom inside hexagon
grid <- expand.grid(
  x = seq(-0.62, 0.62, length.out = 80),
  y = seq(-0.55, 0.60, length.out = 80)
)
r2 <- (grid$x / 0.48)^2 + ((grid$y - 0.05) / 0.52)^2
grid$val <- ifelse(
  r2 <= 1.0,
  0.25 + 0.55 * exp(-((r2 - 0.75)^2) / 0.04) +
    0.35 * exp(-((grid$x - 0.14)^2 + (grid$y - 0.08)^2) / 0.015) +
    0.35 * exp(-((grid$x + 0.14)^2 + (grid$y - 0.08)^2) / 0.015),
  NA_real_
)
grid <- grid[!is.na(grid$val), ]

p <- ggplot() +
  geom_polygon(data = hex_df, aes(x = x, y = y), fill = "#0B132B", color = "#3A86FF", linewidth = 3) +
  geom_tile(data = grid, aes(x = x, y = y, fill = val), width = 0.018, height = 0.018) +
  scale_fill_viridis_c(option = "mako", guide = "none") +
  annotate("text", x = 0, y = -0.58, label = "dicomtk", color = "#FFFFFF", size = 8.5, fontface = "bold") +
  annotate("text", x = 0, y = -0.76, label = "DCMTK 3.7.1 • Rcpp • AI", color = "#8ECAE6", size = 3.2) +
  coord_fixed(xlim = c(-1.08, 1.08), ylim = c(-1.08, 1.08)) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "transparent", color = NA),
    panel.background = element_rect(fill = "transparent", color = NA)
  )

ggsave("man/figures/logo.png", plot = p, width = 3.2, height = 3.2, dpi = 300, bg = "transparent")
cat("Generated man/figures/logo.png\n")
