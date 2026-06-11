/// 사진 메타데이터 모델
class PhotoModel {
  final String id;
  final String filename;
  final String? takenAt;
  final double? latitude;
  final double? longitude;
  final String? placeName;
  final bool isBackedUp;
  final bool isFavorite;
  final String? thumbnailPath;
  final String? localThumbnailPath;
  final String? localPreviewPath;
  final List<String> persons;
  final int? fileSize;
  final String? cameraModel;

  PhotoModel({
    required this.id,
    required this.filename,
    this.takenAt,
    this.latitude,
    this.longitude,
    this.placeName,
    this.isBackedUp = false,
    this.isFavorite = false,
    this.thumbnailPath,
    this.localThumbnailPath,
    this.localPreviewPath,
    this.persons = const [],
    this.fileSize,
    this.cameraModel,
  });

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    return PhotoModel(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      takenAt: json['taken_at'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      placeName: json['place_name'],
      isBackedUp: json['is_backed_up'] == true || json['is_backed_up'] == 1,
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1,
      thumbnailPath: json['thumbnail_path'],
      localThumbnailPath: json['local_thumbnail_path'],
      localPreviewPath: json['local_preview_path'],
      persons: (json['persons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      fileSize: json['file_size'],
      cameraModel: json['camera_model'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filename': filename,
      'taken_at': takenAt,
      'latitude': latitude,
      'longitude': longitude,
      'place_name': placeName,
      'is_backed_up': isBackedUp ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'thumbnail_path': thumbnailPath,
      'local_thumbnail_path': localThumbnailPath,
      'local_preview_path': localPreviewPath,
      'file_size': fileSize,
      'camera_model': cameraModel,
    };
  }

  PhotoModel copyWith({
    bool? isBackedUp,
    bool? isFavorite,
    String? placeName,
    double? latitude,
    double? longitude,
    String? localThumbnailPath,
    String? localPreviewPath,
  }) {
    return PhotoModel(
      id: id,
      filename: filename,
      takenAt: takenAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      placeName: placeName ?? this.placeName,
      isBackedUp: isBackedUp ?? this.isBackedUp,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailPath: thumbnailPath,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      localPreviewPath: localPreviewPath ?? this.localPreviewPath,
      persons: persons,
      fileSize: fileSize,
      cameraModel: cameraModel,
    );
  }
}

/// 장소 모델
class PlaceModel {
  final int id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final String? category;
  final int photoCount;

  PlaceModel({
    required this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.category,
    this.photoCount = 0,
  });

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      address: json['address'],
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      category: json['category'],
      photoCount: json['photo_count'] ?? 0,
    );
  }
}

/// 인물 모델
class PersonModel {
  final int id;
  final String name;
  final int photoCount;
  final String? sampleThumbnail;

  PersonModel({
    required this.id,
    required this.name,
    this.photoCount = 0,
    this.sampleThumbnail,
  });

  factory PersonModel.fromJson(Map<String, dynamic> json) {
    return PersonModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      photoCount: json['photo_count'] ?? 0,
      sampleThumbnail: json['sample_thumbnail'],
    );
  }
}
