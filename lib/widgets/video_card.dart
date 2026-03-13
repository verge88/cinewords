import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/video_provider.dart';
import '../models/video_item.dart';

class VideoCard extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;
  final bool isCompact;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final difficultyColor = Color(video.difficultyColorValue);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (video.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: video.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: Icon(Icons.play_circle_outline,
                              size: 48, color: cs.onSurfaceVariant),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.broken_image_outlined,
                            size: 48, color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.movie_outlined,
                          size: 48, color: cs.onSurfaceVariant),
                    ),

                  // Duration badge
                  if (video.formattedDuration.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          video.formattedDuration,
                          style: tt.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  // Difficulty badge
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: difficultyColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        video.difficultyLabel,
                        style: tt.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  // Favorite toggle
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Consumer<VideoProvider>(
                      builder: (context, provider, _) {
                        final isFav = provider.isFavorite(video.id);
                        return IconButton(
                          onPressed: () => provider.toggleFavorite(video),
                          icon: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                            color: isFav ? Colors.red : Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.2),
                          ),
                        );
                      },
                    ),
                  ),

                  // Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Info
            Padding(
              padding: EdgeInsets.all(isCompact ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: (isCompact ? tt.titleSmall : tt.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (video.channelName != null) ...[
                        Icon(Icons.person_outline,
                            size: isCompact ? 12 : 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            video.channelName!,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant, fontSize: isCompact ? 10 : null),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isCompact) const SizedBox(width: 12),
                      ],
                      if (!isCompact) ...[
                        Icon(Icons.text_fields_rounded,
                            size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${video.totalUniqueWords} words',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}