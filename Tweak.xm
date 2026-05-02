// Original tweak: LiveSafari, by Skitty
// Turn Safari's icon into a real compass

#import "Tweak.h"

static NSString *LSRootPath(NSString *path) {
	static NSString *jbRoot = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		jbRoot = [@"/var/jb" copy];
	});
	return [jbRoot stringByAppendingString:path];
}

static CGFloat const LSNeedleScale = 0.86;

static BOOL LSIsValidSize(CGSize size) {
	return isfinite(size.width) && isfinite(size.height) && size.width > 0.0 && size.height > 0.0;
}

static UIImage *LSImage(NSString *basename) {
	CGFloat scale = [UIScreen mainScreen].scale;
	NSString *suffix = (scale >= 3.0) ? @"@3x" : @"@2x";
	NSString *relativePath = [NSString stringWithFormat:@"/Library/Application Support/LiveSafariReborn/%@%@.png", basename, suffix];
	NSString *path = LSRootPath(relativePath);

	UIImage *image = [UIImage imageWithContentsOfFile:path];
	if (!image) return nil;

	if (image.scale != scale) {
		image = [UIImage imageWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
	}
	return image;
}

%subclass SBSafariIconImageView : SBLiveIconImageView

%property (nonatomic, retain) CLLocationManager *locationManager;
%property (nonatomic, retain) UIImageView *needle;

- (UIImage *)squareContentsImage {
	UIImage *image = LSImage(@"background");
	return image ?: %orig;
}

- (UIImage *)contentsImage {
	UIImage *image = LSImage(@"background");
	if (!image) return %orig;

	CGSize size = image.size;
	if (!LSIsValidSize(size)) return %orig;

	if ([self respondsToSelector:@selector(_currentOverlayImage)]) {
		UIImage *maskImg = [UIImage imageWithData:UIImageJPEGRepresentation([self _currentOverlayImage], 1)];
		if (!maskImg) return %orig;

		CGImageRef maskRef = maskImg.CGImage;
		CGImageRef mask = CGImageMaskCreate(CGImageGetWidth(maskRef), CGImageGetHeight(maskRef), CGImageGetBitsPerComponent(maskRef), CGImageGetBitsPerPixel(maskRef), CGImageGetBytesPerRow(maskRef), CGImageGetDataProvider(maskRef), NULL, false);
		CGImageRef masked = CGImageCreateWithMask(image.CGImage, mask);

		CGImageRelease(mask);

		if (!masked) return %orig;

		UIImage *maskedImage = [UIImage imageWithCGImage:masked scale:image.scale orientation:image.imageOrientation];
		CGImageRelease(masked);

		CALayer *maskedLayer = [CALayer layer];
		maskedLayer.frame = CGRectMake(0, 0, size.width, size.height);
		maskedLayer.contents = (id)maskedImage.CGImage;
		maskedLayer.masksToBounds = YES;
		if ([maskedLayer respondsToSelector:@selector(setCornerCurve:)]) {
			maskedLayer.cornerCurve = kCACornerCurveContinuous;
		}

		CGFloat cornerRadius = self.continuousCornerRadius;
		CGSize boundsSize = self.bounds.size;
		if (LSIsValidSize(boundsSize) && boundsSize.width > 0.0) {
			CGFloat factor = size.width / boundsSize.width;
			if (isfinite(factor) && factor > 0.0) cornerRadius *= factor;
		}
		maskedLayer.cornerRadius = cornerRadius;

		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
		[maskedLayer renderInContext:UIGraphicsGetCurrentContext()];
		UIImage *roundedMasked = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();

		return roundedMasked ?: maskedImage;
	}

	CALayer *imageLayer = [CALayer layer];
	imageLayer.frame = CGRectMake(0, 0, size.width, size.height);
	imageLayer.contents = (id)image.CGImage;

	imageLayer.masksToBounds = YES;
	if ([imageLayer respondsToSelector:@selector(setCornerCurve:)]) {
		imageLayer.cornerCurve = kCACornerCurveContinuous;
	}
	CGFloat cornerRadius = self.continuousCornerRadius;
	CGSize boundsSize = self.bounds.size;
	if (LSIsValidSize(boundsSize) && boundsSize.width > 0.0) {
		CGFloat factor = size.width / boundsSize.width;
		if (isfinite(factor) && factor > 0.0) cornerRadius *= factor;
	}
	imageLayer.cornerRadius = cornerRadius;

	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
	[imageLayer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *roundedImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return roundedImage;
}

- (void)setIcon:(id)arg1 location:(long long)arg2 animated:(BOOL)arg3 {
	%orig;

	if (!self.needle) {
		self.needle = [[UIImageView alloc] initWithImage:LSImage(@"needle")];
		self.needle.contentMode = UIViewContentModeScaleAspectFit;
		self.needle.bounds = self.bounds;
		self.needle.transform = CGAffineTransformMakeScale(LSNeedleScale, LSNeedleScale);
		[self.needle setCenter:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))];
		[self addSubview:self.needle];

		self.locationManager = [[CLLocationManager alloc] init];
		self.locationManager.delegate = self;
		[self.locationManager startUpdatingHeading];
	}
}

- (void)setPaused:(BOOL)paused {
	%orig;
	if (paused) {
		[self.locationManager stopUpdatingHeading];
	} else {
		[self.locationManager startUpdatingHeading];
	}
}

%new
- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
	if ([self isAnimationAllowed]) {
		[UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
			CGAffineTransform scale = CGAffineTransformMakeScale(LSNeedleScale, LSNeedleScale);
			CGAffineTransform rotation = CGAffineTransformMakeRotation(-newHeading.magneticHeading*M_PI/180);
			self.needle.transform = CGAffineTransformConcat(scale, rotation);
		} completion:nil];
	}
}

%new
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
	NSLog(@"[LiveSafariReborn] Error: %@", error);
}

%new
- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
	return NO;
}

- (void)dealloc {
	[self.locationManager stopUpdatingHeading];
	[self.needle release];
	[self.locationManager release];
	%orig;
}

%end

%hook SBIcon

- (Class)iconImageViewClassForLocation:(long long)arg1 {
	if ([[self leafIdentifier] isEqualToString:@"com.apple.mobilesafari"]) {
		return %c(SBSafariIconImageView);
	}
	return %orig;
}

%end
