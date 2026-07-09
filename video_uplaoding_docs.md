For lesson uplaoding , 

{{ROOT_URL}}/course/module/lesson/upload (POST)
Req body 1.
{
  "moduleID": 16,
  "videoFilename": "my-video.mp4",
  "videoContentType": "video/mp4",
  "videoFileSize": 15454545
}
Resposne 

{
    "success": true,
    "statusCode": 201,
    "message": "Presigned URL generated successfully",
    "data": {
        "isMultipart": false,
        "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/6359b8c7-6466-45f1-87e3-673f91ae7e3c.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034120Z&X-Amz-Expires=3600&X-Amz-Signature=7df0b7f709f590ad4c0745adbcd9b870e57a22a6681e7ea9bed517c94643e391&X-Amz-SignedHeaders=host&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=PutObject",
        "fileUrl": "https://d3ptrmo399jwse.cloudfront.net/videos/courses/3/6359b8c7-6466-45f1-87e3-673f91ae7e3c.mp4",
        "key": "videos/courses/3/6359b8c7-6466-45f1-87e3-673f91ae7e3c.mp4",
        "expiresIn": "1 hour"
    },
    "errors": null
}, 

{
  "moduleID": 16,
  "videoFilename": "my-video.mp4",
  "videoContentType": "video/mp4",
  "videoFileSize": 25454545
} ,

{
    "success": true,
    "statusCode": 201,
    "message": "Presigned URL generated successfully",
    "data": {
        "isMultipart": true,
        "uploadId": "D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ",
        "key": "videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4",
        "fileUrl": "https://d3ptrmo399jwse.cloudfront.net/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4",
        "totalParts": 5,
        "parts": [
            {
                "partNumber": 1,
                "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034237Z&X-Amz-Expires=86400&X-Amz-Signature=e1ecbb087fe2ae611646ee4a86e44c37288ca77c48c73f9f7d8fe76b0f45724f&X-Amz-SignedHeaders=host&partNumber=1&uploadId=D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=UploadPart"
            },
            {
                "partNumber": 2,
                "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034237Z&X-Amz-Expires=86400&X-Amz-Signature=2864c255875cfbd8e6be02e4f58e4f6b86948ef61784276967f5fbf9bf3f1c13&X-Amz-SignedHeaders=host&partNumber=2&uploadId=D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=UploadPart"
            },
            {
                "partNumber": 3,
                "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034237Z&X-Amz-Expires=86400&X-Amz-Signature=86cb90a862f95271604cf20b277fd139cb0052855bc1f0a83d91ecf88f2c3acd&X-Amz-SignedHeaders=host&partNumber=3&uploadId=D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=UploadPart"
            },
            {
                "partNumber": 4,
                "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034237Z&X-Amz-Expires=86400&X-Amz-Signature=78bd1e4fe2e6619336c9242427ba483fe848ececdd055909f2d0abe6fe740366&X-Amz-SignedHeaders=host&partNumber=4&uploadId=D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=UploadPart"
            },
            {
                "partNumber": 5,
                "uploadUrl": "https://eduverse-uploads.s3.ap-south-1.amazonaws.com/videos/courses/3/3d9402ee-0f6e-419b-9608-1058248904a5.mp4?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=AKIAWMPIE4TC6IK7Q46L%2F20260709%2Fap-south-1%2Fs3%2Faws4_request&X-Amz-Date=20260709T034237Z&X-Amz-Expires=86400&X-Amz-Signature=c96f851287bf82cb16a4895529a39731ab8a243b3c8b27967eb392549960cf02&X-Amz-SignedHeaders=host&partNumber=5&uploadId=D5GmdEe_ljPsf6r7ymBXa7_ffhXFrHHduDF9kUzCF24WPBMbwoGx6BmnpygYAIhpUPS8DxQFiUbabmRmsGGHGPCdhuoeYJkuK5nOBL0lf4ba9mFu3BSnjBm2pO8UAqCJ&x-amz-checksum-crc32=AAAAAA%3D%3D&x-amz-sdk-checksum-algorithm=CRC32&x-id=UploadPart"
            }
        ],
        "expiresIn": "24 hours"
    },
    "errors": null
} , 

Then video-post/upload/complete (POST) for any multipart (Course intro ,lesson , video post , resource ) same eendpoint

{key
: 
"videos/2f713639-380f-4667-97d1-66f7784b5a94.mp4"
parts
: 
[{partNumber: 1, eTag: ""956303491f6b97f1f7a691a5467b945a""},…]
0
: 
{partNumber: 1, eTag: ""956303491f6b97f1f7a691a5467b945a""}
eTag
: 
"\"956303491f6b97f1f7a691a5467b945a\""
partNumber
: 
1
1
: 
{partNumber: 2, eTag: ""a0a5101181746902b25e93fe13bd29ab""}
eTag
: 
"\"a0a5101181746902b25e93fe13bd29ab\""
partNumber
: 
2
2
: 
{partNumber: 3, eTag: ""1f3f617cdcd0b8a3d4c1e01314b91157""}
eTag
: 
"\"1f3f617cdcd0b8a3d4c1e01314b91157\""
partNumber
: 
3
3
: 
{partNumber: 4, eTag: ""b0ccc147f7dd81995ce4b5f94f8673f8""}
eTag
: 
"\"b0ccc147f7dd81995ce4b5f94f8673f8\""
partNumber
: 
4
uploadId
: 
"RUTKTGPt27a.fylWGiGl9XYqjLFqZENKqRGzcFguqvCtunXN7_LIiwol6p4gkgYqenGIBTc33WaODeb.dh1fedjT0jeqGU.xhYSVOi.rZIgxsXuoFkG1kBYoFPcdThCC"
}
{
  "key": "videos/uuid.mp4",
  "uploadId": "abc123uploadId",
  "parts": [
    {
      "partNumber": 1,
      "eTag": "\"abc123def456\""
    }
  ]
}

resposne 
{
    "success": true,
    "statusCode": 201,
    "message": "Success",
    "data": {
        "fileUrl": "https://d3ptrmo399jwse.cloudfront.net/videos/2f713639-380f-4667-97d1-66f7784b5a94.mp4"
    },
    "errors": null
}

Then lastly for publishing in server for lesson , 

Endpoitn course/module/lesson (PSOT)

{
  "title": "Introduction to Programming",
  "moduleId": 16,
  "videoUrl": "https://d3ptrmo399jwse.cloudfront.net/videos/courses/1/b7607eff-8928-4f85-998f-a80cf948f5fd.mp4",
  "duration": 20,
  "fileSize": 13344
}

And response 

{
    "success": true,
    "statusCode": 201,
    "message": "Lesson created successfully",
    "data": {
        "id": 33,
        "title": "Introduction to Programming",
        "order": 2,
        "moduleId": 16,
        "video": {
            "id": 36,
            "videoUrl": "https://d3ptrmo399jwse.cloudfront.net/videos/courses/1/b7607eff-8928-4f85-998f-a80cf948f5fd.mp4",
            "duration": 20,
            "fileSize": 13344
        },
        "createdAt": "2026-07-09T03:46:42.595Z"
    },
    "errors": null
}
