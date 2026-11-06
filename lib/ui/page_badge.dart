import 'package:flutter/material.dart';

/// 「N」页角标：多页作品在网格里只占一张卡，得让人知道点进去还有图。
/// 样式与详情页的 `R-18` 角标同一套（黑底白字小药丸）。
class PageBadge extends StatelessWidget {
  const PageBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_none, size: 9, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
