#import "Tweak.h"

static CGFloat const LSNeedleScale = 0.86;
static CLLocationDegrees const LSHeadingFilter = 1.0;

static NSString *LSRootPath(NSString *path) {
	return [@"/var/jb" stringByAppendingString:path];
}

static BOOL LSIsValidSize(CGSize size) {
	return isfinite(size.width) && isfinite(size.height) && size.width > 0.0 && size.height > 0.0;
}

static UIImage *LSLoadImage(NSString *basename) {
	CGFloat scale = [UIScreen mainScreen].scale;
	NSString *suffix = (scale >= 3.0) ? @"@3x" : @"@2x";
	NSString *relativePath = [NSString stringWithFormat:@"/Library/Application Support/LiveSafariReborn/%@%@.png", basename, suffix];
	UIImage *image = [[UIImage alloc] initWithContentsOfFile:LSRootPath(relativePath)];

	if (image && image.scale != scale) {
		UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage
													 scale:scale
											 orientation:image.imageOrientation];
		[image release];
		image = scaledImage;
	}

	return image;
}

static UIImage *LSBackgroundImage(void) {
	static UIImage *image = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		image = LSLoadImage(@"background");
	});
	return image;
}

static UIImage *LSNeedleImage(void) {
	static UIImage *image = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		image = LSLoadImage(@"needle");
	});
	return image;
}

static CLLocationDegrees LSHeadingDifference(CLLocationDegrees first, CLLocationDegrees second) {
	CLLocationDegrees difference = fabs(first - second);
	return MIN(difference, 360.0 - difference);
}

@class SBSafariIconImageView;

@interface LSHeadingCoordinator : NSObject <CLLocationManagerDelegate> {
	CLLocationManager *_locationManager;
	NSHashTable *_subscribers;
	BOOL _isUpdating;
	CLLocationDegrees _lastHeading;
}
+ (instancetype)sharedCoordinator;
- (void)addSubscriber:(SBSafariIconImageView *)subscriber;
- (void)removeSubscriber:(SBSafariIconImageView *)subscriber;
@end

@implementation LSHeadingCoordinator

+ (instancetype)sharedCoordinator {
	static LSHeadingCoordinator *coordinator = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		coordinator = [[self alloc] init];
	});
	return coordinator;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_subscribers = [[NSHashTable weakObjectsHashTable] retain];
		_locationManager = [[CLLocationManager alloc] init];
		_locationManager.delegate = self;
		_locationManager.headingFilter = LSHeadingFilter;
		_lastHeading = -1.0;
	}
	return self;
}

- (void)addSubscriber:(SBSafariIconImageView *)subscriber {
	if (!subscriber) return;

	[_subscribers addObject:subscriber];
	if (!_isUpdating && _subscribers.count > 0 && [CLLocationManager headingAvailable]) {
		_isUpdating = YES;
		[_locationManager startUpdatingHeading];
	}

	if (_lastHeading >= 0.0) {
		[subscriber ls_applyHeading:_lastHeading];
	}
}

- (void)removeSubscriber:(SBSafariIconImageView *)subscriber {
	if (subscriber) [_subscribers removeObject:subscriber];

	if (_isUpdating && _subscribers.count == 0) {
		[_locationManager stopUpdatingHeading];
		_isUpdating = NO;
	}
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
	CLLocationDegrees heading = newHeading.magneticHeading;
	if (newHeading.headingAccuracy < 0.0 || !isfinite(heading)) return;
	if (_lastHeading >= 0.0 && LSHeadingDifference(heading, _lastHeading) < LSHeadingFilter) return;

	_lastHeading = heading;
	for (SBSafariIconImageView *subscriber in _subscribers.allObjects) {
		[subscriber ls_applyHeading:heading];
	}
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	if (error.code == kCLErrorDenied) {
		[_locationManager stopUpdatingHeading];
		_isUpdating = NO;
	}
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
	return NO;
}

- (void)dealloc {
	[_locationManager stopUpdatingHeading];
	_locationManager.delegate = nil;
	[_locationManager release];
	[_subscribers release];
	[super dealloc];
}

@end

%subclass SBSafariIconImageView : SBLiveIconImageView

%property (nonatomic, retain) UIImageView *needle;
%property (nonatomic, retain) NSNumber *ls_pausedState;

- (UIImage *)squareContentsImage {
	UIImage *image = LSBackgroundImage();
	return image ?: %orig;
}

- (UIImage *)contentsImage {
	UIImage *image = LSBackgroundImage();
	if (!image) return %orig;

	CGSize size = image.size;
	if (!LSIsValidSize(size)) return %orig;

	if ([self respondsToSelector:@selector(_currentOverlayImage)]) {
		UIImage *overlayImage = [self _currentOverlayImage];
		NSData *overlayData = overlayImage ? UIImageJPEGRepresentation(overlayImage, 1.0) : nil;
		UIImage *maskImage = overlayData ? [UIImage imageWithData:overlayData] : nil;
		if (!maskImage) return %orig;

		CGImageRef maskRef = maskImage.CGImage;
		CGImageRef mask = CGImageMaskCreate(CGImageGetWidth(maskRef),
														  CGImageGetHeight(maskRef),
														  CGImageGetBitsPerComponent(maskRef),
														  CGImageGetBitsPerPixel(maskRef),
														  CGImageGetBytesPerRow(maskRef),
														  CGImageGetDataProvider(maskRef),
														  NULL,
														  false);
		CGImageRef masked = mask ? CGImageCreateWithMask(image.CGImage, mask) : nil;
		if (mask) CGImageRelease(mask);
		if (!masked) return %orig;

		UIImage *maskedImage = [UIImage imageWithCGImage:masked scale:image.scale orientation:image.imageOrientation];
		CGImageRelease(masked);

		CALayer *maskedLayer = [CALayer layer];
		maskedLayer.frame = CGRectMake(0.0, 0.0, size.width, size.height);
		maskedLayer.contents = (id)maskedImage.CGImage;
		maskedLayer.masksToBounds = YES;
		if ([maskedLayer respondsToSelector:@selector(setCornerCurve:)]) {
			maskedLayer.cornerCurve = kCACornerCurveContinuous;
		}

		CGFloat cornerRadius = self.continuousCornerRadius;
		CGSize boundsSize = self.bounds.size;
		if (LSIsValidSize(boundsSize)) {
			CGFloat factor = size.width / boundsSize.width;
			if (isfinite(factor) && factor > 0.0) cornerRadius *= factor;
		}
		maskedLayer.cornerRadius = cornerRadius;

		UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
		[maskedLayer renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *roundedMaskedImage = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();

		UIImage *result = roundedMaskedImage ?: maskedImage;
		return result;
	}

	CALayer *imageLayer = [CALayer layer];
	imageLayer.frame = CGRectMake(0.0, 0.0, size.width, size.height);
	imageLayer.contents = (id)image.CGImage;
	imageLayer.masksToBounds = YES;
	if ([imageLayer respondsToSelector:@selector(setCornerCurve:)]) {
		imageLayer.cornerCurve = kCACornerCurveContinuous;
	}

	CGFloat cornerRadius = self.continuousCornerRadius;
	CGSize boundsSize = self.bounds.size;
	if (LSIsValidSize(boundsSize)) {
		CGFloat factor = size.width / boundsSize.width;
		if (isfinite(factor) && factor > 0.0) cornerRadius *= factor;
	}
	imageLayer.cornerRadius = cornerRadius;

	UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
	[imageLayer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return roundedImage ?: image;
}

- (void)setIcon:(id)icon location:(long long)location animated:(BOOL)animated {
	%orig;

	if (!self.needle) {
		UIImage *needleImage = LSNeedleImage();
		if (needleImage) {
			UIImageView *needleView = [[UIImageView alloc] initWithImage:needleImage];
			needleView.contentMode = UIViewContentModeScaleAspectFit;
			needleView.bounds = CGRectMake(0.0, 0.0, self.bounds.size.width, self.bounds.size.height);
			needleView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
			needleView.transform = CGAffineTransformMakeScale(LSNeedleScale, LSNeedleScale);
			self.needle = needleView;
			[needleView release];
			[self addSubview:self.needle];
		}
	}

	if (self.window && !self.ls_pausedState.boolValue) {
		[[LSHeadingCoordinator sharedCoordinator] addSubscriber:self];
	}
}

- (void)layoutSubviews {
	%orig;
	CGFloat cornerRadius = self.continuousCornerRadius;
	if (isfinite(cornerRadius) && cornerRadius > 0.0) {
		self.layer.masksToBounds = YES;
		self.layer.cornerRadius = cornerRadius;
		if ([self.layer respondsToSelector:@selector(setCornerCurve:)]) {
			self.layer.cornerCurve = kCACornerCurveContinuous;
		}
	}

	if (!self.needle) return;

	CGRect needleBounds = CGRectMake(0.0, 0.0, self.bounds.size.width, self.bounds.size.height);
	CGPoint needleCenter = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
	if (!CGRectEqualToRect(self.needle.bounds, needleBounds)) self.needle.bounds = needleBounds;
	if (!CGPointEqualToPoint(self.needle.center, needleCenter)) self.needle.center = needleCenter;
}

- (void)didMoveToWindow {
	%orig;
	if (self.window && !self.ls_pausedState.boolValue) {
		[[LSHeadingCoordinator sharedCoordinator] addSubscriber:self];
	} else {
		[[LSHeadingCoordinator sharedCoordinator] removeSubscriber:self];
	}
}

- (void)setPaused:(BOOL)paused {
	%orig;
	self.ls_pausedState = [NSNumber numberWithBool:paused];
	if (paused || !self.window) {
		[[LSHeadingCoordinator sharedCoordinator] removeSubscriber:self];
	} else {
		[[LSHeadingCoordinator sharedCoordinator] addSubscriber:self];
	}
}

- (void)prepareForReuse {
	[[LSHeadingCoordinator sharedCoordinator] removeSubscriber:self];
	%orig;
}

%new
- (void)ls_applyHeading:(CLLocationDegrees)heading {
	if (!self.needle || ![self isAnimationAllowed]) return;

	CGAffineTransform scale = CGAffineTransformMakeScale(LSNeedleScale, LSNeedleScale);
	CGAffineTransform rotation = CGAffineTransformMakeRotation(-heading * M_PI / 180.0);
	CGAffineTransform transform = CGAffineTransformConcat(scale, rotation);
	CALayer *needleLayer = self.needle.layer;
	CALayer *presentationLayer = needleLayer.presentationLayer;
	CGAffineTransform currentTransform = presentationLayer ? presentationLayer.affineTransform : needleLayer.affineTransform;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	needleLayer.affineTransform = transform;
	[CATransaction commit];

	CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"affineTransform"];
	animation.fromValue = [NSValue valueWithCGAffineTransform:currentTransform];
	animation.toValue = [NSValue valueWithCGAffineTransform:transform];
	animation.duration = 0.18;
	animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
	[needleLayer addAnimation:animation forKey:@"LSHeadingAnimation"];
}

- (void)dealloc {
	[[LSHeadingCoordinator sharedCoordinator] removeSubscriber:self];
	self.needle = nil;
	self.ls_pausedState = nil;
	%orig;
}

%end

%hook SBIcon

- (Class)iconImageViewClassForLocation:(long long)location {
	if ([[self leafIdentifier] isEqualToString:@"com.apple.mobilesafari"]) {
		return %c(SBSafariIconImageView);
	}
	return %orig;
}

%end
