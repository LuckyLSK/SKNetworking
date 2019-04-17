//
//  SKNetworking.m
//  SKNetworking_Example
//
//  Created by 李烁凯 on 2019/4/9.
//  Copyright © 2019 luckyLSK. All rights reserved.
//

#import "SKNetworking.h"
#import "AFNetworking.h"
#import "AFNetworkActivityIndicatorManager.h"
#import <CommonCrypto/CommonDigest.h>

@interface SKURLCache : NSURLCache

@end

static NSString       *SKURLCacheExpirationKey = @"SKURLCacheExpiration";

static NSTimeInterval SKURLCacheExpirationInterval = 7 * 24 * 60 * 60;

@interface SKURLCache()

@end

@implementation SKURLCache

+ (instancetype)standardURLCache {
    static SKURLCache *_standardURLCache = nil;
    
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _standardURLCache = [[SKURLCache alloc]
                             initWithMemoryCapacity:MAX_CACHE_SIZE
                             diskCapacity:5 * MAX_CACHE_SIZE
                             diskPath:nil];
    });
    return _standardURLCache;
}

- (id)cachedResponseForRequest:(NSURLRequest *)request {
    NSCachedURLResponse *cachedResponse = [super cachedResponseForRequest:request];
    
    if (cachedResponse) {
        NSDate *cacheDate = cachedResponse.userInfo[SKURLCacheExpirationKey];
        
        NSDate *cacheExpirationDate = [cacheDate dateByAddingTimeInterval:SKURLCacheExpirationInterval];
        
        if ([cacheExpirationDate compare:[NSDate date]] == NSOrderedAscending) {
            [self removeCachedResponseForRequest:request];
            return nil;
        }
    }
    
    id responseObj = [NSJSONSerialization JSONObjectWithData:cachedResponse.data options:NSJSONReadingAllowFragments error:nil];
    
    return responseObj;
}

- (void)storeCachedResponse:(id)response
               responseObjc:(id)responseObjc
                 forRequest:(NSURLRequest *)request {
    NSData *data = [NSJSONSerialization dataWithJSONObject:responseObjc options:NSJSONWritingPrettyPrinted error:nil];
    
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    
    userInfo[SKURLCacheExpirationKey] = [NSDate date];
    
    NSCachedURLResponse *modifiedCachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response data:data userInfo:userInfo storagePolicy:0];
    
    [super storeCachedResponse:modifiedCachedResponse forRequest:request];
}

@end

static NSMutableArray      *requestTasks;

static NSMutableDictionary *headers;

static SKNetworkStatus     networkStatus;

static NSTimeInterval      requestTimeout = SK_REQUEST_TIMEOUT;

@implementation SKNetworking

#pragma 任务管理
+ (NSMutableArray *)allTasks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (requestTasks == nil) {
            requestTasks = [[NSMutableArray alloc] init];
        }
    });
    return requestTasks;
}

+ (void)configHttpHeaders:(NSDictionary *)httpHeaders {
    headers = httpHeaders.mutableCopy;
    [headers enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj) {
            [self.manager.requestSerializer setValue:headers[key] forHTTPHeaderField:key];
        }
    }];
}

+ (void)setupTimeout:(NSTimeInterval)timeout {
    requestTimeout = timeout;
}

+ (void)cancelAllRequest {
    @synchronized(self) {
        [[self allTasks] enumerateObjectsUsingBlock:^(SKURLSessionTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([task isKindOfClass:[SKURLSessionTask class]]) {
                [task cancel];
            }
        }];
        [[self allTasks] removeAllObjects];
    };
}

+ (void)cancelRequestWithURL:(NSString *)url {
    @synchronized(self) {
        [[self allTasks] enumerateObjectsUsingBlock:^(SKURLSessionTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([task isKindOfClass:[SKURLSessionTask class]]
                && [task.currentRequest.URL.absoluteString hasSuffix:url]) {
                [task cancel];
                [[self allTasks] removeObject:task];
                return;
            }
        }];
    };
}

#pragma SESSION管理设置
+ (AFHTTPSessionManager *)manager {
    
    static AFHTTPSessionManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
        
        manager = [AFHTTPSessionManager manager];
        
        /**
         *  默认请求和返回的数据类型
         */
        manager.requestSerializer = [AFHTTPRequestSerializer serializer];
        manager.responseSerializer = [AFJSONResponseSerializer serializer];
        manager.requestSerializer.stringEncoding = NSUTF8StringEncoding;
        
        /**
         *  取出NULL值
         */
        AFJSONResponseSerializer *serializer = [AFJSONResponseSerializer serializer];
        [serializer setRemovesKeysWithNullValues:YES];
        
        
        /**
         *  如果不设置支持类型，可能会出现如下错误：
         *
         连接出错 Error Domain=com.alamofire.error.serialization.response Code=-1016
         "Request failed: unacceptable content-type: text/html" UserInfo=
         {com.alamofire.serialization.response.error.response=<NSHTTPURLResponse: 0x7f93fad1c4b0>
         { URL: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx }
         { status code: 200, headers { .....}
         ......
         22222c22 626f6172 64696422 3a226e65 77735f73 68656875 69375f62 6273222c 22707469 6d65223a 22323031 362d3033 2d303320 31313a30 323a3435 227d5d7d>,
         NSLocalizedDescription=Request failed: unacceptable content-type: text/html}
         */
        manager.responseSerializer.acceptableContentTypes = [NSSet setWithArray:@[@"application/json", @"application/xml",@"text/html", @"text/json", @"text/plain", @"text/javascript", @"text/xml", @"image/*"]];
    });
    
    manager.requestSerializer.timeoutInterval = requestTimeout;
    [self detectNetworkStaus];
    
    if ([self totalCacheSize] > MAX_CACHE_SIZE) [self clearCaches];
    
    return manager;
}

+ (void)updateRequestSerializerType:(SKSerializerType)requestType responseSerializer:(SKSerializerType)responseType {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    
    if (requestType) {
        switch (requestType) {
            case SKHTTPSerializer: {
                manager.requestSerializer = [AFHTTPRequestSerializer serializer];
                break;
            }
            case SKJSONSerializer: {
                manager.requestSerializer = [AFJSONRequestSerializer serializer];
                break;
            }
            default:
                break;
        }
    }
    if (responseType) {
        switch (responseType) {
            case SKHTTPSerializer: {
                manager.responseSerializer = [AFHTTPResponseSerializer serializer];
                break;
            }
            case SKJSONSerializer: {
                manager.responseSerializer = [AFJSONResponseSerializer serializer];
                break;
            }
            default:
                break;
        }
    }
}

#pragma 请求业务GET,POST
+ (SKURLSessionTask *)requestWithUrl:(NSString *)url
                              params:(NSDictionary *)params
                            useCache:(BOOL)useCache
                         httpMedthod:(SKRequestType)httpMethod
                       progressBlock:(SKNetWorkingProgress)progressBlock
                        successBlock:(SKResponseSuccessBlock)successBlock
                           failBlock:(SKResponseFailBlock)failBlock {
    
    //构建GET请求的字符串
    NSString *getUrl = [NSString stringWithFormat:@"%@?", url];
    for (NSString *key in [params allKeys]) {
        getUrl = [getUrl stringByAppendingFormat:@"%@=%@&", key, [params objectForKey:key]];
    }
    //    NSLog(@"%@", [getUrl substringToIndex:getUrl.length - 1]);
    AFHTTPSessionManager *manager = [self manager];
    SKURLSessionTask *session;
    
    if (httpMethod == SKPOSTRequest) {
        
        id response = [SKNetworking getCacheResponseWithURL:url params:params];
        successBlock && response && useCache ? successBlock(response) : nil;
        if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
            failBlock ? failBlock(SK_ERROR, NO) : nil;
            return nil;
        }
        
        session = [manager POST:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
            if (progressBlock) {
                progressBlock(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
            }
        } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            successBlock ? successBlock(responseObject) : nil;
            
            NSLog(@"\n\n<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< \n\n POST URL : %@ \n\n<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n result : %@ \n\n <<<<<<<<<<<<<<<<<<<<<<\n" , [getUrl substringToIndex:getUrl.length - 1], responseObject);
            
            
            
            if (useCache) {
                [self cacheResponseObject:responseObject
                                  request:url
                                   params:params];
            }
            
            [[self allTasks] removeObject:task];
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            
            if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
                failBlock ? failBlock(error, NO) : nil;
            }else{
                failBlock ? failBlock(error, YES) : nil;
            }
            
            
            [[self allTasks] removeObject:task];
        }];
        
    }else if(httpMethod == SKGETRequest){
        
        id response = [SKNetworking getCacheResponseWithURL:url params:params];
        
        if (successBlock && response && useCache) {
            successBlock(response);
            return nil;
        }
        //        successBlock && response && useCache ? successBlock(response) : nil;
        
        if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
            failBlock ? failBlock(SK_ERROR, NO) : nil;
            return nil;
        }
        
        session = [manager GET:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
            if (progressBlock) {
                progressBlock(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
            }
        } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            /*
             if (responseObject) {
             [urlCache storeCachedResponse:task.response
             responseObjc:responseObject
             forRequest:request];
             }
             */
            
            NSLog(@"\n\n<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< \n\n GET URL : %@ \n\n<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n\n result : %@ \n\n <<<<<<<<<<<<<<<<<<<<<<\n" , [getUrl substringToIndex:getUrl.length - 1], responseObject);
            
            if (useCache) {
                [self cacheResponseObject:responseObject
                                  request:url
                                   params:params];
            }
            
            successBlock ? successBlock(responseObject) : nil;
            
            [[self allTasks] removeObject:task];
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            
            if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
                failBlock ? failBlock(error, NO) : nil;
            }else{
                failBlock ? failBlock(error, YES) : nil;
            }
            
            [[self allTasks] removeObject:task];
        }];
    }
    if (session) {
        [[self allTasks] addObject:session];
    }
    return  session;
}

#pragma 图片 文件上传下载方法
+ (SKURLSessionTask *)uploadWithImageArr:(NSArray *)imageArr
                                     url:(NSString *)url
                                    name:(NSString *)name
                                    type:(NSString *)type
                                  params:(NSDictionary *)params
                           progressBlock:(SKNetWorkingProgress)progressBlock
                            successBlock:(SKResponseSuccessBlock)successBlock
                               failBlock:(SKResponseFailBlock)failBlock {
    
    //构建GET请求的字符串
    NSString *getUrl = [NSString stringWithFormat:@"%@&", url];
    for (NSString *key in [params allKeys]) {
        getUrl = [getUrl stringByAppendingFormat:@"%@=%@&", key, [params objectForKey:key]];
    }
    
    NSLog(@"GET URL > %@", [getUrl substringToIndex:getUrl.length - 1]);
    
    AFHTTPSessionManager *manager = [self manager];
    
    SKURLSessionTask *session = [manager POST:url parameters:params constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        
        for (int i = 0; i < imageArr.count; i++) {
            
            NSData *imageData = UIImageJPEGRepresentation(imageArr[i], 0.4);
            
            NSString *imageFileName;
            
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            
            formatter.dateFormat = @"yyyyMMddHHmmss";
            
            NSString *str = [formatter stringFromDate:[NSDate date]];
            
            imageFileName = [NSString stringWithFormat:@"%@%d.png", str,i];
            
            NSString *blockImageType = type;
            
            if (type.length == 0) blockImageType = @"image/jpeg";
            
            [formData appendPartWithFileData:imageData name:name fileName:imageFileName mimeType:blockImageType];
        }
        
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        if (progressBlock) {
            progressBlock(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
        }
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        successBlock ? successBlock(responseObject) : nil;
        [[self allTasks] removeObject:task];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
        if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
            failBlock ? failBlock(error, NO) : nil;
        }else{
            failBlock ? failBlock(error, YES) : nil;
        }
        [[self allTasks] removeObject:task];
    }];
    [session resume];
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    return session;
}

/**
 *  文件上传接口
 *
 *  @param url              上传文件接口地址
 *  @param file             上传文件路径
 *  @param progressBlock    上传进度
 *    @param successBlock     成功回调
 *    @param failBlock        失败回调
 *
 *  @return 返回的对象中可取消请求
 */
+ (SKURLSessionTask *)uploadFileWithUrl:(NSString *)url
                                   file:(NSString *)file
                                   type:(NSString *)type
                                   name:(NSString *)name
                                 params:(NSDictionary *)params
                          progressBlock:(SKNetWorkingProgress)progressBlock
                           successBlock:(SKResponseSuccessBlock)successBlock
                              failBlock:(SKResponseFailBlock)failBlock{
    
    NSData *da = [NSData dataWithContentsOfFile:file];
    if (!type.length) {
        type = @"application/octet-stream";
    }
    NSArray *tempArr = [file componentsSeparatedByString:@"."];
    AFHTTPSessionManager *manager = [self manager];
    
    SKURLSessionTask *session = [manager POST:url parameters:params constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        
        NSString *fileName = [NSString stringWithFormat:@"temp.%@", tempArr.lastObject];
        [formData appendPartWithFileData:da name:name fileName:fileName mimeType:type];
        
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        if (progressBlock) {
            progressBlock(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
        }
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        successBlock ? successBlock(responseObject) : nil;
        [[self allTasks] removeObject:task];
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
        if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
            failBlock ? failBlock(error, NO) : nil;
        }else{
            failBlock ? failBlock(error, YES) : nil;
        }
        [[self allTasks] removeObject:task];
    }];
    [session resume];
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    return session;
    
    
    /*
     SKURLSessionTask *session = [manager POST:url parameters:params constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
     
     [formData appendPartWithFileURL:fileUrl name:name fileName:@"yuyin.amr" mimeType:type error:nil];
     
     
     } progress:^(NSProgress * _Nonnull uploadProgress) {
     if (progressBlock) {
     progressBlock(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
     }
     } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
     successBlock ? successBlock(responseObject) : nil;
     [[self allTasks] removeObject:task];
     } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
     
     if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
     failBlock ? failBlock(error, NO) : nil;
     }else{
     failBlock ? failBlock(error, YES) : nil;
     }
     [[self allTasks] removeObject:task];
     }];
     [session resume];
     
     if (session) {
     [[self allTasks] addObject:session];
     }
     return session;
     */
}

+ (SKURLSessionTask *)downloadWithUrl:(NSString *)url
                           saveToPath:(NSURL *)saveToPath
                        progressBlock:(SKNetWorkingProgress)progressBlock
                         successBlock:(SKResponseSuccessBlock)successBlock
                            failBlock:(SKResponseFailBlock)failBlock {
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    AFHTTPSessionManager *manager = [self manager];
    SKURLSessionTask *session = nil;
    
    session = [manager downloadTaskWithRequest:downloadRequest progress:^(NSProgress * _Nonnull downloadProgress) {
        if (progressBlock) {
            progressBlock(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
        }
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        
        return saveToPath;
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        [[self allTasks] removeObject:session];
        
        successBlock ? successBlock(filePath.absoluteString) : nil;
        
        if (networkStatus == SKNetworkStatusNotReachable ||  networkStatus == SKNetworkStatusUnknown) {
            failBlock && error ? failBlock(error, NO) : nil;
        }else{
            failBlock && error ? failBlock(error, YES) : nil;
        }
    }];
    
    [session resume];
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    
    return session;
}

#pragma mark - 网络状态的检测
+ (void)detectNetworkStaus {
    AFNetworkReachabilityManager *reachabilityManager = [AFNetworkReachabilityManager sharedManager];
    [reachabilityManager startMonitoring];
    [reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        if (status == AFNetworkReachabilityStatusNotReachable){
            networkStatus = SKNetworkStatusNotReachable;
        }else if (status == AFNetworkReachabilityStatusUnknown){
            networkStatus = SKNetworkStatusUnknown;
        }else if (status == AFNetworkReachabilityStatusReachableViaWWAN || status == AFNetworkReachabilityStatusReachableViaWiFi){
            networkStatus = SKNetworkStatusNormal;
        }
    }];
}

#pragma 缓存处理
+ (void)cacheResponseObject:(id)responseObject
                    request:(NSString *)request
                     params:(NSDictionary *)params {
    if (request && responseObject && ![responseObject isKindOfClass:[NSNull class]]) {
        NSString *directoryPath = DIRECTORYPATH;
        
        NSError *error = nil;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:nil]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
        }
        
        NSString *originString = [NSString stringWithFormat:@"%@+%@",request, params];
        NSString *path = [directoryPath stringByAppendingPathComponent:[self md5:originString]];
        NSDictionary *dict = (NSDictionary *)responseObject;
        
        NSData *data = nil;
        if ([dict isKindOfClass:[NSData class]]) {
            data = responseObject;
        } else {
            data = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
        }
        if (data && error == nil) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
        }
    }
}

+ (NSString *)md5:(NSString *)string {
    if (string == nil || [string length] == 0) {
        return nil;
    }
    unsigned char digest[CC_MD5_DIGEST_LENGTH], i;
    CC_MD5([string UTF8String], (int)[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding], digest);
    NSMutableString *ms = [NSMutableString string];
    
    for (i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [ms appendFormat:@"%02x", (int)(digest[i])];
    }
    
    return [ms copy];
}

+ (id)getCacheResponseWithURL:(NSString *)url
                       params:(NSDictionary *)params {
    id cacheData = nil;
    if (url) {
        NSString *directoryPath = DIRECTORYPATH;
        NSString *originString = [NSString stringWithFormat:@"%@+%@",url,params];
        NSString *path = [directoryPath stringByAppendingPathComponent:[self md5:originString]];
        NSData *data = [[NSFileManager defaultManager] contentsAtPath:path];
        if (data) {
            cacheData = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        }
    }
    return cacheData;
}

+ (unsigned long long)totalCacheSize {
    NSString *directoryPath = DIRECTORYPATH;
    
    BOOL isDir = NO;
    unsigned long long total = 0;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:&isDir]) {
        if (isDir) {
            NSError *error = nil;
            NSArray *array = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPath error:&error];
            if (error == nil) {
                for (NSString *subpath in array) {
                    NSString *path = [directoryPath stringByAppendingPathComponent:subpath];
                    NSDictionary *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                                          error:&error];
                    if (!error) {
                        total += [dict[NSFileSize] unsignedIntegerValue];
                    }
                }
            }
        }
    }
    return total;
}

+ (void)clearCaches {
    NSString *directoryPath = DIRECTORYPATH;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:nil]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:directoryPath error:&error];
    }
}

@end
