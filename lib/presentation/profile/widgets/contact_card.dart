import 'package:flutter/material.dart';
import 'package:tapguard/data/models/contact_model.dart';

class ContactCard extends StatelessWidget {
  final ContactModel contact;
  final VoidCallback onRemove;
  final Function(bool) onEmergencyToggle;
  final VoidCallback onEdit;
  final bool isEmergencyContact;

  const ContactCard({
    super.key,
    required this.contact,
    required this.onRemove,
    required this.onEmergencyToggle,
    required this.onEdit,
    this.isEmergencyContact = false,
  });

  Color _priorityColor(int priority) {
    if (priority == 1) return const Color(0xFFFF3B30); // red - highest
    if (priority == 2) return const Color(0xFFFF9500); // orange - medium
    return Colors.grey; // low/default
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF7C4DFF);
    const emergencyColor = Color(0xFFFF3B30);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmergencyContact
              ? emergencyColor.withValues(alpha: 0.3)
              : primaryColor.withValues(alpha: 0.1),
          width: isEmergencyContact ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Contact header with profile and details
            Row(
              children: [
                // Profile avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isEmergencyContact
                        ? emergencyColor.withValues(alpha: 0.15)
                        : primaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isEmergencyContact
                          ? Icons.emergency_share_rounded
                          : Icons.person_rounded,
                      color: isEmergencyContact ? emergencyColor : primaryColor,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Contact name and phone
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              contact.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                                fontFamily: 'Poppins',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Priority badge
                          if (contact.priority <= 3)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _priorityColor(contact.priority).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'P${contact.priority}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _priorityColor(contact.priority),
                                  fontFamily: 'Poppins',
                                ),
                              ),
                            ),
                          if (isEmergencyContact)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: emergencyColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.priority_high_rounded,
                                    size: 12,
                                    color: emergencyColor,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Emergency',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: emergencyColor,
                                      fontFamily: 'Poppins',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact.phoneNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF999999),
                          fontFamily: 'Poppins',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Contact status badges
            Row(
              children: [
                if (contact.isVerified)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: Color(0xFF34C759),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF34C759),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (contact.allowsLocationSharing)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha:0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: primaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Shares Location',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: primaryColor,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                // Edit button
                Expanded(
                  child: GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Emergency toggle button
                Expanded(
                  child: GestureDetector(
                    onTap: () => onEmergencyToggle(!isEmergencyContact),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isEmergencyContact
                            ? emergencyColor.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isEmergencyContact
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 16,
                            color: isEmergencyContact
                                ? emergencyColor
                                : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isEmergencyContact ? 'Emergency' : 'Set Primary',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isEmergencyContact
                                  ? emergencyColor
                                  : Colors.grey,
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Delete button
                Expanded(
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: Color(0xFFFF3B30),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Remove',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF3B30),
                              fontFamily: 'Poppins',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
